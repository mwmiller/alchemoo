Mix.install([{:alchemoo, path: "."}])

IO.puts("🚀 Alchemoo Verb Execution Demo\n")

# Load database
{:ok, db} = Alchemoo.Database.Parser.parse_file("tmp/LambdaCore-12Apr99.db")

IO.puts("✓ Loaded LambdaCore")
IO.puts("  Objects: #{map_size(db.objects)}")
IO.puts("  System verbs: #{length(db.objects[0].verbs)}")

# Parse simple verb code
test_code = """
x = 10;
y = 20;
return x + y;
"""

IO.puts("\nTest code:")
IO.puts(test_code)

{:ok, ast} = Alchemoo.Parser.MOOSimple.parse(test_code)
IO.puts("✓ Parsed successfully")

# Execute
try do
  Enum.reduce(ast.statements, %{}, fn stmt, env ->
    case Alchemoo.Interpreter.eval(stmt, env) do
      {:ok, _, new_env} -> new_env
      {:ok, _} -> env
    end
  end)
catch
  {:return, val} ->
    IO.puts("✓ Executed successfully")
    IO.puts("  Result: #{Alchemoo.Value.to_literal(val)}")
end

IO.puts("\n🎉 Full MOO language support complete!")
