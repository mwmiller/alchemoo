defmodule Alchemoo.Value do
  @moduledoc """
  MOO value representation and operations.

  MOO has 5 basic types:
  - NUM: integers
  - OBJ: object references
  - STR: strings
  - ERR: error codes
  - LIST: lists of values
  """

  @type moo_value ::
          {:num, integer()}
          | {:obj, integer()}
          | {:str, String.t()}
          | {:err, atom()}
          | {:list, [moo_value()]}
          | :clear

  @type t :: moo_value()

  # Error codes from MOO
  @errors ~w(
    E_NONE E_TYPE E_DIV E_PERM E_PROPNF E_VERBNF E_VARNF
    E_INVIND E_RECMOVE E_MAXREC E_RANGE E_ARGS E_NACC
    E_INVARG E_QUOTA E_FLOAT
  )a

  @doc """
  Create a MOO number value.
  """
  def num(n) when is_integer(n), do: {:num, n}

  @doc """
  Create a MOO object reference.
  """
  def obj(n) when is_integer(n), do: {:obj, n}

  @doc """
  Create a MOO string value.
  """
  def str(s) when is_binary(s), do: {:str, s}

  @doc """
  Create a MOO error value.
  """
  def err(e) when e in @errors, do: {:err, e}

  @doc """
  Create a MOO list value.
  """
  def list(items) when is_list(items), do: {:list, items}

  @doc """
  Convert Elixir value to MOO value.
  """
  def from_elixir(n) when is_integer(n), do: num(n)
  def from_elixir(s) when is_binary(s), do: str(s)
  def from_elixir(items) when is_list(items), do: list(Enum.map(items, &from_elixir/1))
  def from_elixir({:obj, n}), do: obj(n)
  def from_elixir({:err, e}), do: err(e)
  def from_elixir(v), do: v

  @doc """
  Convert MOO value to Elixir value.
  """
  def to_elixir({:num, n}), do: n
  def to_elixir({:obj, n}), do: n
  def to_elixir({:str, s}), do: s
  def to_elixir({:err, e}), do: {:error, e}
  def to_elixir({:list, items}), do: Enum.map(items, &to_elixir/1)

  @doc """
  Get the type of a MOO value.
  """
  def typeof({:num, _}), do: :num
  def typeof({:obj, _}), do: :obj
  def typeof({:str, _}), do: :str
  def typeof({:err, _}), do: :err
  def typeof({:list, _}), do: :list

  @doc """
  Check if value is true (MOO semantics: 0 is false, everything else is true).
  """
  def truthy?({:num, 0}), do: false
  def truthy?(_), do: true

  @doc """
  Compare two MOO values for equality.
  """
  def equal?({type, val1}, {type, val2}), do: val1 == val2
  def equal?(_, _), do: false

  @doc """
  Get length of a string or list.
  """
  def length({:str, s}), do: {:num, String.length(s)}
  def length({:list, items}), do: {:num, Kernel.length(items)}
  def length(_), do: {:err, :E_TYPE}

  @doc """
  Index into a string or list (1-based indexing like MOO).
  """
  def index({:str, s}, {:num, i}) when i > 0 do
    case String.at(s, i - 1) do
      nil -> {:err, :E_RANGE}
      char -> {:str, char}
    end
  end

  def index({:list, items}, {:num, i}) when i > 0 do
    case Enum.at(items, i - 1) do
      nil -> {:err, :E_RANGE}
      val -> val
    end
  end

  def index(_, _), do: {:err, :E_TYPE}

  @doc """
  Get range from string or list (1-based, inclusive).
  """
  def range({:str, s}, start_idx, end_idx) when start_idx > 0 and end_idx >= start_idx do
    len = String.length(s)
    start_idx = max(1, start_idx)
    end_idx = min(len, end_idx)

    case start_idx > len do
      true ->
        {:str, ""}

      false ->
        {:str, String.slice(s, start_idx - 1, end_idx - start_idx + 1)}
    end
  end

  def range({:list, items}, start_idx, end_idx) when start_idx > 0 and end_idx >= start_idx do
    len = Kernel.length(items)
    start_idx = max(1, start_idx)
    end_idx = min(len, end_idx)

    case start_idx > len do
      true ->
        {:list, []}

      false ->
        {:list, Enum.slice(items, start_idx - 1, end_idx - start_idx + 1)}
    end
  end

  def range(_, _, _), do: {:err, :E_TYPE}

  @doc """
  Concatenate two strings or lists.
  """
  def concat({:str, s1}, {:str, s2}), do: {:str, s1 <> s2}
  def concat({:list, l1}, {:list, l2}), do: {:list, l1 ++ l2}
  def concat(_, _), do: {:err, :E_TYPE}

  @doc """
  Convert value to string representation.
  """
  def to_literal({:num, n}), do: Integer.to_string(n)
  def to_literal({:obj, n}), do: "##{n}"
  def to_literal({:str, s}), do: s
  def to_literal({:err, e}), do: Atom.to_string(e)

  def to_literal({:list, items}) do
    "{" <> Enum.map_join(items, ", ", &to_literal/1) <> "}"
  end
end
