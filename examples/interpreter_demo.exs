#!/usr/bin/env elixir

Mix.install([{:alchemoo, path: "."}])

alias Alchemoo.Parser.Expression
alias Alchemoo.Interpreter
alias Alchemoo.Value

IO.puts("🧪 Alchemoo MOO Interpreter Demo\n")

examples = [
  "42",
  "1 + 2 * 3",
  "(1 + 2) * 3",
  "10 / 2",
  "5 == 5",
  "5 != 6",
  "{1, 2, 3}",
  "\"hello\"",
  "#123"
]

Enum.each(examples, fn code ->
  {:ok, ast, _} = Expression.parse(code)
  {:ok, result} = Interpreter.eval(ast)
  
  IO.puts("  #{code}")
  IO.puts("  => #{Value.to_literal(result)}\n")
end)

IO.puts("\n✅ Interpreter working!")
