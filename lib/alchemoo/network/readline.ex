defmodule Alchemoo.Network.Readline do
  @moduledoc """
  Implements server-side line editing (Readline-like) for SSH connections.
  Handles ANSI escape sequences, backspace, and history.
  """
  require Logger

  defstruct [
    :socket,
    :transport,
    buffer: "",
    cursor: 0,
    history: [],
    history_index: -1,
    current_save: ""
  ]

  @ansi_clear_line "\e[2K\r"
  @ansi_cursor_left "\e[D"
  @ansi_cursor_right "\e[C"

  def new(socket, transport) do
    %__MODULE__{
      socket: socket,
      transport: transport
    }
  end

  @doc """
  Process a single byte or sequence of bytes from the network.
  Returns {:ok, state} or {:line, line, state}.
  """
  def handle_input(data, state) do
    # Handle multi-byte sequences (like ANSI arrows) or single chars
    process_bytes(data, state)
  end

  defp process_bytes(<<>>, state), do: {:ok, state}

  # Enter / Return
  defp process_bytes(<<key, rest::binary>>, state) when key in [?\r, ?\n] do
    line = state.buffer
    send_raw(state, "\r\n")

    new_history =
      if line != "" and List.first(state.history) != line do
        [line | Enum.take(state.history, 99)]
      else
        state.history
      end

    {:line, line,
     %{state | buffer: "", cursor: 0, history: new_history, history_index: -1, current_save: ""}}
    |> handle_rest(rest)
  end

  # Backspace (Ctrl-H or Del)
  defp process_bytes(<<key, rest::binary>>, state) when key in [8, 127] do
    if state.cursor > 0 do
      {left, right} = String.split_at(state.buffer, state.cursor - 1)
      new_buffer = left <> String.slice(right, 1..-1//1)
      new_cursor = state.cursor - 1

      new_state = %{state | buffer: new_buffer, cursor: new_cursor}
      redraw(new_state)
      process_bytes(rest, new_state)
    else
      process_bytes(rest, state)
    end
  end

  # ANSI Escape Sequences
  # Up
  defp process_bytes(<<27, ?[, ?A, rest::binary>>, state) do
    handle_history(-1, state) |> then(&process_bytes(rest, &1))
  end

  # Down
  defp process_bytes(<<27, ?[, ?B, rest::binary>>, state) do
    handle_history(1, state) |> then(&process_bytes(rest, &1))
  end

  # Right
  defp process_bytes(<<27, ?[, ?C, rest::binary>>, state) do
    new_cursor = min(String.length(state.buffer), state.cursor + 1)

    if new_cursor != state.cursor do
      send_raw(state, @ansi_cursor_right)
    end

    process_bytes(rest, %{state | cursor: new_cursor})
  end

  # Left
  defp process_bytes(<<27, ?[, ?D, rest::binary>>, state) do
    new_cursor = max(0, state.cursor - 1)

    if new_cursor != state.cursor do
      send_raw(state, @ansi_cursor_left)
    end

    process_bytes(rest, %{state | cursor: new_cursor})
  end

  # Ctrl-A (Home)
  defp process_bytes(<<1, rest::binary>>, state) do
    move_cursor(0, state) |> then(&process_bytes(rest, &1))
  end

  # Ctrl-E (End)
  defp process_bytes(<<5, rest::binary>>, state) do
    move_cursor(String.length(state.buffer), state) |> then(&process_bytes(rest, &1))
  end

  # Ctrl-K (Kill to end)
  defp process_bytes(<<11, rest::binary>>, state) do
    new_buffer = String.slice(state.buffer, 0, state.cursor)
    new_state = %{state | buffer: new_buffer}
    redraw(new_state)
    process_bytes(rest, new_state)
  end

  # Ctrl-L (Clear screen)
  defp process_bytes(<<12, rest::binary>>, state) do
    send_raw(state, "\e[H\e[2J")
    redraw(state)
    process_bytes(rest, state)
  end

  # Ctrl-U (Kill line)
  defp process_bytes(<<21, rest::binary>>, state) do
    new_state = %{state | buffer: "", cursor: 0}
    redraw(new_state)
    process_bytes(rest, new_state)
  end

  # Printable characters
  defp process_bytes(<<char::utf8, rest::binary>>, state) when char >= 32 do
    {left, right} = String.split_at(state.buffer, state.cursor)
    new_buffer = left <> <<char::utf8>> <> right
    new_cursor = state.cursor + 1

    new_state = %{state | buffer: new_buffer, cursor: new_cursor}
    redraw(new_state)
    process_bytes(rest, new_state)
  end

  # Ignore other control chars
  defp process_bytes(<<_char, rest::binary>>, state) do
    process_bytes(rest, state)
  end

  defp handle_rest({:line, line, state}, <<>>), do: {:line, line, state}

  defp handle_rest({:line, line, state}, rest) do
    case process_bytes(rest, state) do
      {:ok, next_state} -> {:line, line, next_state}
      {:line, next_line, next_state} -> {:line, line <> "\n" <> next_line, next_state}
    end
  end

  defp handle_history(dir, state) do
    # dir -1 is Up (back in time), 1 is Down
    new_idx = state.history_index - dir

    # Save current buffer if we just started navigating history
    save = if state.history_index == -1, do: state.buffer, else: state.current_save

    cond do
      new_idx == -1 ->
        new_state = %{
          state
          | buffer: save,
            cursor: String.length(save),
            history_index: -1,
            current_save: ""
        }

        redraw(new_state)
        new_state

      new_idx >= 0 and new_idx < length(state.history) ->
        entry = Enum.at(state.history, new_idx)

        new_state = %{
          state
          | buffer: entry,
            cursor: String.length(entry),
            history_index: new_idx,
            current_save: save
        }

        redraw(new_state)
        new_state

      true ->
        state
    end
  end

  defp move_cursor(pos, state) do
    diff = pos - state.cursor

    if diff < 0 do
      send_raw(state, String.duplicate(@ansi_cursor_left, abs(diff)))
    else
      send_raw(state, String.duplicate(@ansi_cursor_right, diff))
    end

    %{state | cursor: pos}
  end

  defp redraw(state) do
    # Clear line, print buffer, return to cursor
    send_raw(state, @ansi_clear_line)
    send_raw(state, state.buffer)

    # Return to cursor position
    back = String.length(state.buffer) - state.cursor

    if back > 0 do
      send_raw(state, String.duplicate(@ansi_cursor_left, back))
    end
  end

  defp send_raw(state, data) do
    state.transport.send(state.socket, data)
  end
end
