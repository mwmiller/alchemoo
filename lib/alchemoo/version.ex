defmodule Alchemoo.Version do
  @moduledoc """
  Server version and information.
  """

  @version "0.2.0"

  def version, do: @version

  def banner do
    banner("Alchemoo")
  end

  def banner(moo_name) do
    """
    ---------------------------------------------------------
    Welcome to #{moo_name}
    Running on Alchemoo v#{@version} (BEAM)
    ---------------------------------------------------------
    Type 'connect <name> <password>' to log in.
    Type 'create <name> <password>' to create a new player.
    Type 'help' for more commands.
    """
  end
end
