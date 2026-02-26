defmodule Alchemoo.Database.Object do
  @moduledoc """
  Represents a MOO object with its verbs, properties, and relationships.
  """

  defstruct [
    :id,
    :name,
    :owner,
    :location,
    :first_content_id,
    :next_id,
    :parent,
    :first_child_id,
    :sibling_id,
    flags: 0,
    contents: [],
    children: [],
    verbs: [],
    properties: [],
    overridden_properties: %{},
    all_properties: [],
    temp_values: []
  ]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          flags: integer(),
          owner: integer(),
          location: integer(),
          first_content_id: integer(),
          next_id: integer(),
          parent: integer(),
          first_child_id: integer(),
          sibling_id: integer(),
          contents: [integer()],
          children: [integer()],
          verbs: [Alchemoo.Database.Verb.t()],
          properties: [Alchemoo.Database.Property.t()],
          overridden_properties: %{String.t() => Alchemoo.Database.Property.t()}
        }
end
