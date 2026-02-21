defmodule Alchemoo.Database.Verb do
  @moduledoc """
  Represents a verb (method) on a MOO object.
  """

  defstruct [
    :name,
    :owner,
    :perms,
    :prep,
    :args,
    :code
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          owner: integer(),
          perms: String.t(),
          prep: integer(),
          args: tuple(),
          code: [String.t()]
        }
end
