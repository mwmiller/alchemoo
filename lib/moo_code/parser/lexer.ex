defmodule Alchemoo.MOOCode.Parser.Lexer do
  @moduledoc """
  Character-by-character lexer for MOO code.
  No regex - pure pattern matching for maintainability.
  """

  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

  @type token :: {type(), value(), position()}
  @type type ::
          :keyword
          | :ident
          | :op
          | :dot
          | :colon
          | :bang
          | :lparen
          | :rparen
          | :lbracket
          | :rbracket
          | :lbrace
          | :rbrace
          | :comma
          | :semi
          | :backtick
          | :squote
          | :string
          | :int
          | :float
          | :obj
          | :global
          | :any
          | :optional
          | :dollar
  @type value :: atom() | String.t() | integer() | float()
  @type position :: {line :: integer(), column :: integer()}

  @type t :: %__MODULE__{
          line: integer(),
          column: integer(),
          tokens: [token()]
        }

  defstruct line: 1, column: 1, tokens: []

  # --- Public API ---

  @doc """
  Lex source code into tokens.
  """
  @spec lex(String.t() | charlist()) :: {:ok, [token()]} | {:error, term()}
  def lex(source) when is_binary(source),
    do: source |> String.to_charlist() |> do_lex(%__MODULE__{})

  def lex(charlist) when is_list(charlist),
    do: do_lex(charlist, %__MODULE__{})

  # --- Main Lexer Loop ---

  defp do_lex([], state), do: {:ok, Enum.reverse(state.tokens)}

  # Whitespace
  defp do_lex([c | rest], state) when c in [?\s, ?\t, ?\r],
    do: do_lex(rest, advance(state, 1))

  defp do_lex([?\n | rest], state) do
    state = advance(state, 1)
    do_lex(rest, %{state | line: state.line + 1, column: 1})
  end

  # Comments and Object IDs
  defp do_lex([?# | rest] = input, state) do
    case rest do
      [c | _] when (c >= ?0 and c <= ?9) or c == ?- -> lex_object_id(input, state)
      _ -> skip_comment(rest, state)
    end
  end

  # Strings
  defp do_lex([?" | rest], state) do
    case lex_string(rest, []) do
      {:ok, str, remaining} ->
        token = {:string, str, {state.line, state.column}}
        do_lex(remaining, add_token(state, token, length(rest) - length(remaining) + 2))

      error ->
        error
    end
  end

  # Globals ($foo) or $ alone (end of list/string index)
  defp do_lex([?$ | rest], state) do
    {name, remaining} = take_while(rest, &identifier_char?/1)

    if name == [] do
      # Just a $ by itself - treat as special "end" marker
      token = {:dollar, :"$", {state.line, state.column}}
      do_lex(rest, add_token(state, token, 1))
    else
      token = {:global, to_string(name), {state.line, state.column}}
      do_lex(remaining, add_token(state, token, length(name) + 1))
    end
  end

  # Optional variables (?foo)
  defp do_lex([?? | rest], state) do
    {name, remaining} = take_while(rest, &identifier_char?/1)

    if name == [] do
      # Just a ? by itself - treat as ternary operator
      token = {:op, :"?", {state.line, state.column}}
      do_lex(rest, add_token(state, token, 1))
    else
      token = {:optional, to_string(name), {state.line, state.column}}
      do_lex(remaining, add_token(state, token, length(name) + 1))
    end
  end

  # Identifiers and keywords
  defp do_lex([c | rest], state) when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ do
    {name, remaining} = take_while([c | rest], &identifier_char?/1)
    {type, value} = classify_identifier(to_string(name))
    token = {type, value, {state.line, state.column}}
    do_lex(remaining, add_token(state, token, length(name)))
  end

  # Numbers
  defp do_lex([c | rest], state) when c >= ?0 and c <= ?9,
    do: lex_number([c | rest], state)

  # Multi-char operators (priority order matters)
  for {pattern, op} <- [
        {[?=, ?=], :==},
        {[?!, ?=], :!=},
        {[?<, ?=], :<=},
        {[?>, ?=], :>=},
        {[?&, ?&], :&&},
        {[?|, ?|], :||},
        {[?., ?.], :..},
        {[?=, ?>], :"=>"}
      ] do
    defp do_lex(unquote(pattern) ++ rest, state) do
      token = {:op, unquote(op), {state.line, state.column}}
      do_lex(rest, add_token(state, token, 2))
    end
  end

  # Single-char operators (including | for ternary)
  defp do_lex([c | rest], state) when c in ~c"+-*/%^!<>=@|" do
    token = {:op, char_to_op(c), {state.line, state.column}}
    do_lex(rest, add_token(state, token, 1))
  end

  # Delimiters
  defp do_lex([c | rest], state) when c in ~c".:()[]{} ,;`'?" do
    token = {char_to_token(c), c, {state.line, state.column}}
    do_lex(rest, add_token(state, token, 1))
  end

  # Error
  defp do_lex([c | _], state),
    do: {:error, {:unexpected_char, c, {state.line, state.column}}}

  # --- Character Classification ---

  defp identifier_char?(c),
    do: (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c == ?_

  defp classify_identifier(name) do
    case name do
      "if" -> {:keyword, :if}
      "else" -> {:keyword, :else}
      "elseif" -> {:keyword, :elseif}
      "endif" -> {:keyword, :endif}
      "while" -> {:keyword, :while}
      "endwhile" -> {:keyword, :endwhile}
      "for" -> {:keyword, :for}
      "in" -> {:op, :in}
      "endfor" -> {:keyword, :endfor}
      "return" -> {:keyword, :return}
      "break" -> {:keyword, :break}
      "continue" -> {:keyword, :continue}
      "try" -> {:keyword, :try}
      "except" -> {:keyword, :except}
      "finally" -> {:keyword, :finally}
      "endtry" -> {:keyword, :endtry}
      "ANY" -> {:any, :ANY}
      _ -> {:ident, name}
    end
  end

  # --- Character to Token Type ---

  defp char_to_op(?+), do: :+
  defp char_to_op(?-), do: :-
  defp char_to_op(?*), do: :*
  defp char_to_op(?/), do: :/
  defp char_to_op(?%), do: :%
  defp char_to_op(?^), do: :^
  defp char_to_op(?<), do: :<
  defp char_to_op(?>), do: :>
  defp char_to_op(?=), do: :=
  defp char_to_op(?!), do: :!
  defp char_to_op(?.), do: :.
  defp char_to_op(?:), do: :colon
  defp char_to_op(?@), do: :@
  defp char_to_op(?|), do: :|

  defp char_to_token(c) when c in ~c"+-*/%^!<>=@", do: :op
  defp char_to_token(?:), do: :colon
  defp char_to_token(?.), do: :dot
  defp char_to_token(?!), do: :bang
  defp char_to_token(?(), do: :lparen
  defp char_to_token(?)), do: :rparen
  defp char_to_token(?[), do: :lbracket
  defp char_to_token(?]), do: :rbracket
  defp char_to_token(?{), do: :lbrace
  defp char_to_token(?}), do: :rbrace
  defp char_to_token(?,), do: :comma
  defp char_to_token(?;), do: :semi
  defp char_to_token(?`), do: :backtick
  defp char_to_token(?'), do: :squote
  defp char_to_token(??), do: :"?"
  defp char_to_token(?|), do: :|

  # --- State Helpers ---

  defp advance(state, n), do: %{state | column: state.column + n}

  defp add_token(state, token, cols),
    do: %{state | tokens: [token | state.tokens], column: state.column + cols}

  defp skip_comment(rest, state) do
    {_, remaining} = skip_until(rest, fn c -> c == ?\n end)
    do_lex(remaining, state)
  end

  # --- String Lexing ---

  defp lex_string([?\\, c | rest], acc) when c in ~c"\\nt\"",
    do: lex_string(rest, [escape_char(c) | acc])

  defp lex_string([?" | rest], acc),
    do: {:ok, acc |> Enum.reverse() |> to_string(), rest}

  defp lex_string([c | rest], acc),
    do: lex_string(rest, [c | acc])

  defp lex_string([], _acc),
    do: {:error, :unterminated_string}

  defp escape_char(?n), do: ?\n
  defp escape_char(?t), do: ?\t
  defp escape_char(c), do: c

  # --- Number Lexing ---

  defp lex_number(input, state) do
    {int_part, rest} = take_while(input, &digit?/1)

    case rest do
      [?., d | frac_rest] when d >= ?0 and d <= ?9 ->
        {frac_part, rest2} = take_while(frac_rest, &digit?/1)
        # Handle scientific notation: 1.e5 or 1.5e5
        case rest2 do
          [e | _] when e in ~c"eE" ->
            lex_scientific(int_part ++ [?., d | frac_part], rest2, state)

          _ ->
            lex_float_suffix(int_part ++ [?., d | frac_part], rest2, state)
        end

      [?., e | rest2] when e in ~c"eE" ->
        # Handle 1.e5 format (no fractional digits)
        lex_scientific(int_part ++ [?.], rest2, state)

      [e | _] when e in ~c"eE" ->
        lex_scientific(int_part, rest, state)

      _ ->
        token = {:int, String.to_integer(to_string(int_part)), {state.line, state.column}}
        do_lex(rest, add_token(state, token, length(int_part)))
    end
  end

  defp digit?(c), do: c >= ?0 and c <= ?9

  defp lex_float_suffix(int_part, [e | tail], state) when e in ~c"eE" do
    # This case should be handled in lex_number now, but keep as fallback
    lex_scientific(int_part, [e | tail], state)
  end

  defp lex_float_suffix(int_part, rest, state) do
    {val, _} = Float.parse(to_string(int_part))
    token = {:float, val, {state.line, state.column}}
    do_lex(rest, add_token(state, token, length(int_part)))
  end

  defp lex_scientific(int_part, [e | rest], state) when e in ~c"eE" do
    {sign, rest2} =
      case rest do
        [s | t] when s in ~c"+-" -> {[s], t}
        _ -> {[], rest}
      end

    {exp_digits, rest3} = take_while(rest2, &digit?/1)
    num_str = to_string(int_part ++ [e | sign ++ exp_digits])
    {val, _} = Float.parse(num_str)

    token = {:float, val, {state.line, state.column}}

    do_lex(
      rest3,
      add_token(state, token, length(int_part) + 1 + length(sign) + length(exp_digits))
    )
  end

  # --- Object ID Lexing ---

  defp lex_object_id([?# | rest], state) do
    {sign, rest2} =
      case rest do
        [?- | t] -> {[?-], t}
        _ -> {[], rest}
      end

    {digits, remaining} = take_while(rest2, &digit?/1)

    case digits do
      [] ->
        {:error, {:invalid_object_id, {state.line, state.column}}}

      _ ->
        num_str = to_string(sign ++ digits)
        token = {:obj, String.to_integer(num_str), {state.line, state.column}}
        do_lex(remaining, add_token(state, token, 1 + length(sign) + length(digits)))
    end
  end

  # --- Utility Functions ---

  defp take_while(list, pred), do: do_take_while(list, pred, [])

  defp do_take_while([c | rest], pred, acc) do
    if pred.(c), do: do_take_while(rest, pred, [c | acc]), else: {Enum.reverse(acc), [c | rest]}
  end

  defp do_take_while([], _pred, acc), do: {Enum.reverse(acc), []}

  defp skip_until(list, pred), do: do_skip_until(list, pred)

  defp do_skip_until([c | rest], pred) do
    if pred.(c), do: {c, rest}, else: do_skip_until(rest, pred)
  end

  defp do_skip_until([], _pred), do: {nil, []}
end
