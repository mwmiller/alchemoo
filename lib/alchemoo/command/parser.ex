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

  alias Alchemoo.Database.Prepositions
  alias Alchemoo.Database.Resolver

  @doc """
  Parse a command string into a verb call structure.

  Returns:
    {:ok, %{verb: verb, argstr: argstr, dobj: dobj, prep: prep, iobj: iobj}}
  """
  def parse(command) do
    command = String.trim_leading(command)

    case command do
      "" ->
        {:error, :empty_command}

      _ ->
        {verb, raw_argstr} = extract_verb_and_argstr(command)
        words = String.split(raw_argstr, ~r/\s+/, trim: true)

        case Prepositions.find(words) do
          {:ok, index, prep_str, range} ->
            # Found a preposition!
            # dobj is words before it
            # iobj is words after it
            dobj_words = Enum.slice(words, 0, range.first)
            iobj_words = Enum.drop(words, range.last + 1)

            {:ok,
             %{
               verb: verb,
               argstr: raw_argstr,
               dobj: Enum.join(dobj_words, " "),
               prep: index,
               prepstr: prep_str,
               iobj: Enum.join(iobj_words, " ")
             }}

          {:error, :not_found} ->
            # No preposition, whole argstr is dobj
            {:ok,
             %{
               verb: verb,
               argstr: raw_argstr,
               dobj: raw_argstr,
               # PREP_NONE
               prep: -1,
               prepstr: "",
               iobj: ""
             }}
        end
    end
  end

  defp extract_verb_and_argstr("\"" <> rest), do: {"say", rest}
  defp extract_verb_and_argstr(":" <> rest), do: {"emote", rest}
  defp extract_verb_and_argstr(";" <> rest), do: {"eval", rest}

  defp extract_verb_and_argstr(command) do
    case String.split(command, ~r/\s+/, parts: 2) do
      [verb, rest] -> {verb, rest}
      [verb] -> {verb, ""}
    end
  end

  @doc """
  Find which object to call the verb on.

  Search order:
  1. Player's verbs
  2. Player's location verbs
  3. Direct object verbs (if it's a valid object)
  4. Indirect object verbs (if it's a valid object)
  5. Location "huh" verb (if nothing else matched)
  6. System object #0 "huh" verb
  """
  def find_verb_target(parsed, player_id, db) do
    # Search order:
    # 1. Player's verbs
    # 2. Player's location verbs
    # 3. Direct object verbs
    # 4. Indirect object verbs
    # 5. Fallback to "huh" on location, then #0

    with {:error, :E_VERBNF} <- find_on_object(player_id, parsed, db),
         {:ok, player_obj} <- Map.fetch(db.objects, player_id),
         {:error, :E_VERBNF} <- find_on_object(player_obj.location, parsed, db),
         # Add check for dobj if it was resolved to an object
         {:error, :E_VERBNF} <- find_on_object(Map.get(parsed, :dobj_id, -1), parsed, db),
         # Add check for iobj if it was resolved to an object
         {:error, :E_VERBNF} <- find_on_object(Map.get(parsed, :iobj_id, -1), parsed, db) do
      # Fallback: find "huh" on location, then #0
      # Huh verbs don't check argspecs normally in standard MOO search,
      # but they are called if nothing else matches.
      case find_on_object(player_obj.location, %{parsed | verb: "huh"}, db) do
        {:ok, obj_id, _} -> {:ok, obj_id, "huh"}
        _ -> find_on_object(0, %{parsed | verb: "huh"}, db)
      end
    else
      {:ok, obj_id, verb_name} -> {:ok, obj_id, verb_name}
      _ -> {:error, :E_VERBNF}
    end
  end

  defp find_on_object(obj_id, parsed, db) when obj_id >= 0 do
    case Resolver.find_verb(db, obj_id, parsed) do
      {:ok, _found_id, _verb} -> {:ok, obj_id, parsed.verb}
      _ -> {:error, :E_VERBNF}
    end
  end

  defp find_on_object(_obj_id, _parsed, _db), do: {:error, :E_VERBNF}
end
