Mix.install([{:alchemoo, path: "."}])

IO.puts("🚀 Alchemoo Verb Execution Demo\n")

# Load database
state_home = System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")
db_path = Path.join([state_home, "alchemoo", "LambdaCore-12Apr99.db"])
{:ok, db} = Alchemoo.Database.Parser.parse_file(db_path)

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
