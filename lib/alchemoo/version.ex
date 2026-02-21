defmodule Alchemoo.Version do
  @moduledoc """
  Version information for Alchemoo.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version

  def banner do
    # CONFIG: :alchemoo, :moo_name
    moo_name = Application.get_env(:alchemoo, :moo_name, "Alchemoo")

    # CONFIG: :alchemoo, :welcome_text
    intro_text =
      Application.get_env(:alchemoo, :welcome_text, "A Modern LambdaMOO Server on the BEAM")

    """

    ═══════════════════════════════════════════════════════════

              ✨ #{String.upcase(moo_name)} ✨

              #{intro_text} 💧

              Running Alchemoo v#{@version}

    ═══════════════════════════════════════════════════════════
    """
  end
end
