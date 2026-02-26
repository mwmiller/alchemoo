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
          | {:float, float()}
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
  def to_elixir({:float, n}), do: n
  def to_elixir({:obj, n}), do: n
  def to_elixir({:str, s}), do: s
  def to_elixir({:err, e}), do: {:error, e}
  def to_elixir({:list, items}), do: Enum.map(items, &to_elixir/1)

  @doc """
  Get the type of a MOO value.
  """
  def typeof({:num, _}), do: :num
  def typeof({:float, _}), do: :float
  def typeof({:obj, _}), do: :obj
  def typeof({:str, _}), do: :str
  def typeof({:err, _}), do: :err
  def typeof({:list, _}), do: :list

  @doc """
  Check if value is true (MOO semantics).
  The following values are false:
  - The integer 0
  - The empty string ""
  - The empty list {}
  - Any error value
  All other values are true.
  """
  def truthy?(val) do
    case val do
      {:num, 0} -> false
      {:str, ""} -> false
      {:list, []} -> false
      {:err, _} -> false
      _ -> true
    end
  end

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

  def range({:str, _s}, start_idx, end_idx) when start_idx > 0 and end_idx < start_idx do
    {:str, ""}
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

  def range({:list, _items}, start_idx, end_idx) when start_idx > 0 and end_idx < start_idx do
    {:list, []}
  end

  def range(_, _, _), do: {:err, :E_TYPE}

  @doc """
  Replace range in string or list (1-based, inclusive).
  """
  def set_range({:str, s}, start_idx, end_idx, {:str, replacement}) when start_idx > 0 do
    len = String.length(s)
    insert_at = min(start_idx - 1, len)

    {prefix, suffix} =
      if end_idx < start_idx do
        {
          String.slice(s, 0, insert_at),
          String.slice(s, insert_at, len - insert_at)
        }
      else
        end_clamped = min(end_idx, len)
        delete_count = max(end_clamped - start_idx + 1, 0)

        {
          String.slice(s, 0, insert_at),
          String.slice(s, insert_at + delete_count, len - insert_at - delete_count)
        }
      end

    {:str, prefix <> replacement <> suffix}
  end

  def set_range({:list, items}, start_idx, end_idx, {:list, replacement}) when start_idx > 0 do
    len = Kernel.length(items)
    insert_at = min(start_idx - 1, len)

    {prefix, suffix} =
      if end_idx < start_idx do
        {
          Enum.take(items, insert_at),
          Enum.drop(items, insert_at)
        }
      else
        end_clamped = min(end_idx, len)
        delete_count = max(end_clamped - start_idx + 1, 0)

        {
          Enum.take(items, insert_at),
          Enum.drop(items, insert_at + delete_count)
        }
      end

    {:list, prefix ++ replacement ++ suffix}
  end

  def set_range({:str, _}, _start_idx, _end_idx, _), do: {:err, :E_TYPE}
  def set_range({:list, _}, _start_idx, _end_idx, _), do: {:err, :E_TYPE}
  def set_range(_, _, _, _), do: {:err, :E_TYPE}

  @doc """
  Concatenate two strings or lists.
  """
  def concat({:str, s1}, {:str, s2}), do: {:str, s1 <> s2}
  def concat({:list, l1}, {:list, l2}), do: {:list, l1 ++ l2}
  def concat(_, _), do: {:err, :E_TYPE}

  @doc """
  Set value at index (1-based).
  """
  def set_index({:list, items}, {:num, i}, val) when i > 0 do
    case i <= Kernel.length(items) do
      true -> {:list, List.replace_at(items, i - 1, val)}
      false -> {:err, :E_RANGE}
    end
  end

  def set_index({:str, s}, {:num, i}, {:str, val}) when i > 0 and byte_size(val) == 1 do
    case i <= String.length(s) do
      true ->
        prefix = String.slice(s, 0, i - 1)
        suffix = String.slice(s, i..-1//1)
        {:str, prefix <> val <> suffix}

      false ->
        {:err, :E_RANGE}
    end
  end

  def set_index({:str, _}, {:num, _}, _), do: {:err, :E_TYPE}
  def set_index(_, _, _), do: {:err, :E_TYPE}

  @doc """
  Convert value to string representation.
  """
  def to_literal({:num, n}), do: Integer.to_string(n)
  def to_literal({:float, n}), do: :erlang.float_to_binary(n, [:compact])
  def to_literal({:obj, n}), do: "##{n}"
  def to_literal({:str, s}), do: s
  def to_literal({:err, e}), do: Atom.to_string(e)
  def to_literal(:clear), do: "<clear>"
  def to_literal(:none), do: "<none>"

  def to_literal({:spliced, {:list, items}}) do
    "@" <> to_literal({:list, items})
  end

  def to_literal({:list, items}) do
    "{" <> Enum.map_join(items, ", ", &to_literal/1) <> "}"
  end
end
