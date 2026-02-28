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

  alias Alchemoo.Database.Resolver

  @doc """
  Parse a command string into a verb call structure.

  Returns:
    {:ok, %{verb: verb, dobj: dobj, prep: prep, iobj: iobj}}
  """
  def parse(command) do
    command = String.trim_leading(command)
    {verb, raw_argstr} = extract_verb_and_argstr(command)

    words = String.split(command, ~r/\s+/, trim: true)

    case words do
      [] ->
        {:error, :empty_command}

      [_verb | args_only] ->
        # We still return the tokenized version for dobj/prep/iobj mapping,
        # but we also return the raw argstr.
        parsed = %{
          verb: verb,
          argstr: raw_argstr,
          dobj: Enum.at(args_only, 0),
          prep: Enum.at(args_only, 1),
          iobj: Enum.at(args_only, 2)
        }

        {:ok, parsed}
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
  """
  def find_verb_target(parsed, player_id, db) do
    # Search order:
    # 1. Player's verbs
    # 2. Player's location verbs
    # 3. Direct object verbs
    # 4. Indirect object verbs
    # 5. System object #0
    with {:error, :E_VERBNF} <- find_on_object(player_id, parsed.verb, db),
         {:ok, player_obj} <- Map.fetch(db.objects, player_id),
         {:error, :E_VERBNF} <- find_on_object(player_obj.location, parsed.verb, db),
         # Add check for dobj if it was resolved to an object
         {:error, :E_VERBNF} <- find_on_object(Map.get(parsed, :dobj_id, -1), parsed.verb, db),
         # Add check for iobj if it was resolved to an object
         {:error, :E_VERBNF} <- find_on_object(Map.get(parsed, :iobj_id, -1), parsed.verb, db),
         # Final fallback to #0
         {:error, :E_VERBNF} <- find_on_object(0, parsed.verb, db) do
      {:error, :E_VERBNF}
    else
      {:ok, obj_id, verb_name} -> {:ok, obj_id, verb_name}
      _ -> {:error, :E_VERBNF}
    end
  end

  defp find_on_object(obj_id, verb_name, db) when obj_id >= 0 do
    case Resolver.find_verb(db, obj_id, verb_name) do
      {:ok, _found_id, _verb} -> {:ok, obj_id, verb_name}
      _ -> {:error, :E_VERBNF}
    end
  end

  defp find_on_object(_obj_id, _verb_name, _db), do: {:error, :E_VERBNF}
end
