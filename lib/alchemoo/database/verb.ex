defmodule Alchemoo.Database.Verb do
  @moduledoc """
  Represents a MOO verb with its code, permissions, and argument specification.
  """
  import Bitwise

  defstruct [
    :name,
    :owner,
    :perms,
    :prep,
    :args,
    :code,
    :ast
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          owner: integer(),
          perms: integer() | String.t(),
          prep: integer(),
          args: {atom(), atom(), atom()},
          code: [String.t()],
          ast: Alchemoo.AST.Block.t() | nil
        }

  @doc """
  Check if verb matches a given name, considering aliases.
  """
  def match?(verb, name) do
    verb.name
    |> String.split(" ")
    |> Enum.any?(fn pattern ->
      match_pattern?(pattern, name)
    end)
  end

  @doc """
  Match a single verb name pattern (e.g. "co*nnect") against input.
  """
  def match_pattern?(pattern, input) do
    case String.split(pattern, "*", parts: 2) do
      [exact] ->
        exact == input

      [prefix, rest] ->
        full = prefix <> rest
        String.starts_with?(input, prefix) and String.starts_with?(full, input)
    end
  end

  @doc """
  Decode verb argspec from stored perms/prep flags used in LambdaMOO DB format.
  """
  def args_from_flags(perms, prep) when is_integer(perms) and is_integer(prep) do
    dobj =
      cond do
        (perms &&& 0x10) != 0 -> :any
        (perms &&& 0x20) != 0 -> :this
        true -> :none
      end

    iobj =
      cond do
        (perms &&& 0x40) != 0 -> :any
        (perms &&& 0x80) != 0 -> :none
        true -> :this
      end

    prep_atom = if prep == -1, do: :none, else: String.to_atom(Integer.to_string(prep))
    {dobj, prep_atom, iobj}
  end

  def args_from_flags(_, _), do: nil
end
