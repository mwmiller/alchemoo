defmodule Alchemoo.Database.Prepositions do
  @moduledoc """
  Standard MOO preposition definitions and matching logic.
  Aligned with LambdaMOO db_verbs.c.
  """

  @prep_list [
    "with/using",
    "at/to",
    "in front of",
    "in/inside/into",
    "on top of/on/onto/upon",
    "out of/from inside/from",
    "over",
    "through",
    "under/underneath/beneath",
    "behind",
    "beside",
    "for/about",
    "is",
    "as",
    "off/off of"
  ]

  @doc "Get the list of standard preposition groups."
  def list, do: @prep_list

  @doc "Get the canonical name for a preposition index."
  def name(index) when index >= 0 and index < length(@prep_list) do
    Enum.at(@prep_list, index)
  end

  def name(_), do: nil

  @doc """
  Find a preposition in a list of words.
  Returns `{:ok, index, prep_str, range}` or `{:error, :not_found}`.
  `range` is the range of indices in the word list that matched.
  """
  def find(words) do
    # Try every starting position
    0..(length(words) - 1)//1
    |> Enum.find_value({:error, :not_found}, fn start_idx ->
      case match_at(words, start_idx) do
        {:ok, index, matched_words} ->
          end_idx = start_idx + length(matched_words) - 1
          {:ok, index, Enum.join(matched_words, " "), start_idx..end_idx}

        _ ->
          nil
      end
    end)
  end

  @doc """
  Match a preposition string (like "in front of") to its index.
  """
  def match_str(prep_name) do
    lower_name = String.downcase(prep_name)

    @prep_list
    |> Enum.with_index()
    |> Enum.find_value({:error, :not_found}, fn {group, index} ->
      group
      |> String.split("/")
      |> Enum.any?(fn alias -> String.downcase(alias) == lower_name end)
      |> if(do: {:ok, index}, else: nil)
    end)
  end

  defp match_at(words, start_idx) do
    remaining = Enum.drop(words, start_idx)

    # Try every preposition group
    @prep_list
    |> Enum.with_index()
    |> Enum.find_value(nil, fn {group, index} ->
      find_matching_group(remaining, group, index)
    end)
  end

  defp find_matching_group(remaining, group, index) do
    # Try every alias in the group
    group
    |> String.split("/")
    |> Enum.map(&String.split(&1, " ", trim: true))
    # Sort by length descending to match longest possible alias (e.g. "in front of" before "in")
    |> Enum.sort_by(&length/1, :desc)
    |> Enum.find_value(nil, fn alias_words ->
      if starts_with?(remaining, alias_words) do
        {:ok, index, alias_words}
      else
        nil
      end
    end)
  end

  defp starts_with?(_words, []), do: true

  defp starts_with?([w | rest_words], [a | rest_alias]) do
    if String.downcase(w) == String.downcase(a) do
      starts_with?(rest_words, rest_alias)
    else
      false
    end
  end

  defp starts_with?([], [_ | _]), do: false
end
