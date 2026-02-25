defmodule Alchemoo.Command.Parser do
  @moduledoc """
  Parses MOO commands into verb calls.

  MOO command syntax:
    verb [dobj] [prep] [iobj]

  Examples:
    look
    look me
    get ball
    put ball in box
    give ball to wizard
  """

  @doc """
  Parse a command string into a verb call structure.

  Returns:
    {:ok, %{verb: verb, dobj: dobj, prep: prep, iobj: iobj}}
  """
  def parse(command) do
    words = String.split(command, ~r/\s+/, trim: true)

    case words do
      [] ->
        {:error, :empty_command}

      [verb] ->
        {:ok, %{verb: verb, dobj: nil, prep: nil, iobj: nil}}

      [verb, dobj] ->
        {:ok, %{verb: verb, dobj: dobj, prep: nil, iobj: nil}}

      [verb, dobj, prep] ->
        {:ok, %{verb: verb, dobj: dobj, prep: prep, iobj: nil}}

      [verb, dobj, prep, iobj | _rest] ->
        {:ok, %{verb: verb, dobj: dobj, prep: prep, iobj: iobj}}
    end
  end

  @doc """
  Find which object to call the verb on.

  Search order:
  1. Player's verbs
  2. Player's location verbs
  3. Direct object verbs
  4. Indirect object verbs
  """
  def find_verb_target(parsed, player_id, _db) do
    # For now, just try the player
    # FUTURE: Implement full search order
    {:ok, player_id, parsed.verb}
  end
end
