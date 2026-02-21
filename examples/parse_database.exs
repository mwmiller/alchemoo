#!/usr/bin/env elixir

# Example: Parse and inspect a LambdaMOO database
#
# Usage:
#   ./examples/parse_database.exs /path/to/database.db

Mix.install([{:alchemoo, path: "."}])

[db_path | _] = System.argv()

IO.puts("Parsing #{db_path}...")

case Alchemoo.Database.Parser.parse_file(db_path) do
  {:ok, db} ->
    IO.puts("\n✓ Successfully parsed database!")
    IO.puts("  Format Version: #{db.version}")
    IO.puts("  Objects: #{map_size(db.objects)}")
    
    total_verbs = 
      db.objects
      |> Map.values()
      |> Enum.map(&length(&1.verbs))
      |> Enum.sum()
    
    verbs_with_code =
      db.objects
      |> Map.values()
      |> Enum.flat_map(& &1.verbs)
      |> Enum.count(&(length(&1.code) > 0))
    
    IO.puts("  Total Verbs: #{total_verbs}")
    IO.puts("  Verbs with Code: #{verbs_with_code}")
    
    # Show first object
    IO.puts("\n📦 First Object:")
    first = db.objects[0]
    IO.puts("  ##{first.id}: #{first.name}")
    IO.puts("  Owner: ##{first.owner}")
    IO.puts("  Parent: ##{first.parent}")
    IO.puts("  Verbs: #{length(first.verbs)}")
    IO.puts("  Properties: #{length(first.properties)}")
    
    if length(first.verbs) > 0 do
      first_verb = hd(first.verbs)
      IO.puts("\n  First Verb: #{first_verb.name}")
      IO.puts("  Code lines: #{length(first_verb.code)}")
      
      if length(first_verb.code) > 0 do
        IO.puts("\n  First 3 lines of code:")
        first_verb.code
        |> Enum.take(3)
        |> Enum.each(&IO.puts("    #{&1}"))
      end
    end

  {:error, reason} ->
    IO.puts("\n✗ Failed to parse database: #{inspect(reason)}")
    System.halt(1)
end
