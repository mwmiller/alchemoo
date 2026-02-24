defmodule Alchemoo.Database.Verb do
  @moduledoc """
  Represents a MOO verb with its code, permissions, and argument specification.
  """

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
end
