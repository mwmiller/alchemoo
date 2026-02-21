defmodule Alchemoo.Database.Object do
  @moduledoc """
  Represents a MOO object with its verbs, properties, and relationships.
  """

  defstruct [
    :id,
    :name,
    :flags,
    :owner,
    :location,
    :contents,
    :next,
    :parent,
    :child,
    :sibling,
    verbs: [],
    properties: []
  ]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          flags: integer(),
          owner: integer(),
          location: integer(),
          contents: [integer()],
          next: integer(),
          parent: integer(),
          child: integer(),
          sibling: integer(),
          verbs: [Alchemoo.Database.Verb.t()],
          properties: [Alchemoo.Database.Property.t()]
        }
end
