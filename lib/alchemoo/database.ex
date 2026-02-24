defmodule Alchemoo.Database do
  @moduledoc """
  Represents a complete MOO database.
  """

  alias Alchemoo.Database.Object

  defstruct [
    :version,
    :object_count,
    :clock,
    objects: %{},
    max_object: -1
  ]

  @type t :: %__MODULE__{
          version: integer(),
          object_count: integer(),
          clock: integer(),
          objects: %{integer() => Object.t()},
          max_object: integer()
        }
end
