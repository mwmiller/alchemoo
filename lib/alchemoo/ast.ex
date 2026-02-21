defmodule Alchemoo.AST do
  @moduledoc """
  Abstract Syntax Tree for MOO code.
  """

  # Literals
  defmodule Literal do
    @moduledoc false
    defstruct [:value]
  end

  # Variable reference
  defmodule Var do
    @moduledoc false
    defstruct [:name]
  end

  # Binary operations
  defmodule BinOp do
    @moduledoc false
    defstruct [:op, :left, :right]
  end

  # Unary operations
  defmodule UnaryOp do
    @moduledoc false
    defstruct [:op, :expr]
  end

  # Property access: obj.prop
  defmodule PropRef do
    @moduledoc false
    defstruct [:obj, :prop]
  end

  # Property assignment: obj.prop = value
  defmodule PropAssignment do
    @moduledoc false
    defstruct [:obj, :prop, :value]
  end

  # Verb call: obj:verb(args)
  defmodule VerbCall do
    @moduledoc false
    defstruct [:obj, :verb, :args]
  end

  # Function call: func(args)
  defmodule FuncCall do
    @moduledoc false
    defstruct [:name, :args]
  end

  # List construction
  defmodule ListExpr do
    @moduledoc false
    defstruct [:elements]
  end

  # Index: expr[index]
  defmodule Index do
    @moduledoc false
    defstruct [:expr, :index]
  end

  # Range: expr[start..end]
  defmodule Range do
    @moduledoc false
    defstruct [:expr, :start, :end]
  end

  # Statements
  defmodule If do
    @moduledoc false
    defstruct [:condition, :then_block, :elseif_blocks, :else_block]
  end

  defmodule ElseIf do
    @moduledoc false
    defstruct [:condition, :block]
  end

  defmodule While do
    @moduledoc false
    defstruct [:condition, :body]
  end

  defmodule For do
    @moduledoc false
    defstruct [:var, :range, :body]
  end

  defmodule ForList do
    @moduledoc false
    defstruct [:var, :list, :body]
  end

  defmodule Return do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Break do
    @moduledoc false
    defstruct []
  end

  defmodule Continue do
    @moduledoc false
    defstruct []
  end

  defmodule Assignment do
    @moduledoc false
    defstruct [:target, :value]
  end

  defmodule ExprStmt do
    @moduledoc false
    defstruct [:expr]
  end

  defmodule Block do
    @moduledoc false
    defstruct [:statements]
  end

  defmodule Try do
    @moduledoc false
    defstruct [:body, :except_clauses, :finally_block]
  end

  defmodule Except do
    @moduledoc false
    defstruct [:error_var, :body]
  end
end
