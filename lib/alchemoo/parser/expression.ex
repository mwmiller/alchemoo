defmodule Alchemoo.Parser.Expression do
  @moduledoc """
  Backwards compatibility wrapper for expression parsing.
  Delegates to Alchemoo.MOOCode.Parser.
  """

  alias Alchemoo.MOOCode.{AST, Parser}
  alias Alchemoo.MOOCode.Parser.Lexer

  @doc """
  Parse a MOO expression string into an AST node.
  Returns {:ok, ast, remaining_tokens} for compatibility.
  """
  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  def parse(input) when is_binary(input) do
    with {:ok, tokens} <- Lexer.lex(input) do
      case Parser.parse(tokens) do
        {:ok, %AST.Block{statements: [%AST.ExprStmt{expr: expr}]}} ->
          {:ok, expr, []}

        {:ok, %AST.Block{statements: statements}} ->
          # Return first expression if multiple statements
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          case statements do
            [%AST.ExprStmt{expr: expr} | _] -> {:ok, expr, []}
            _ -> {:ok, nil, []}
          end

        error ->
          error
      end
    end
  end

  def parse(tokens) when is_list(tokens) do
    parse(to_string(tokens))
  end
end
