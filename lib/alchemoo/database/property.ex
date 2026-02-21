defmodule Alchemoo.Database.Property do
  @moduledoc """
  Represents a property on a MOO object.
  """

  defstruct [
    :name,
    :value,
    :owner,
    :perms
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          value: any(),
          owner: integer(),
          perms: String.t()
        }
end
