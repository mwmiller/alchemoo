defmodule Alchemoo.Database.Flags do
  @moduledoc """
  Standard MOO object flags.
  Values aligned with standard LambdaMOO.
  """
  import Bitwise

  @doc "Object represents a player"
  def user, do: 0x0001

  @doc "Object has wizard permissions"
  def wizard, do: 0x0002

  @doc "Object has programmer permissions"
  def programmer, do: 0x0004

  @doc "Object is readable by anyone"
  def read, do: 0x0008

  @doc "Object is writable by anyone"
  def write, do: 0x0010

  @doc "Object can be parented to by anyone"
  def fertile, do: 0x0020

  @doc "Object is anonymous (Format 4+)"
  def anonymous, do: 0x0040

  @doc "Check if a specific flag is set"
  def set?(flags, flag), do: (flags &&& flag) != 0

  @doc "Set a specific flag"
  def set(flags, flag), do: flags ||| flag

  @doc "Clear a specific flag"
  def clear(flags, flag), do: flags &&& Bitwise.bnot(flag)

  defmacro __using__(_opts) do
    quote do
      import Bitwise
      alias Alchemoo.Database.Flags
    end
  end
end
