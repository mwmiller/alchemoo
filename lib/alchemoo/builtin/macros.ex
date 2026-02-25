defmodule Alchemoo.Builtins.Macros do
  @moduledoc """
  Macros for defining MOO built-in functions.
  """
  require Logger

  # Macro to define standard built-ins that don't modify environment
  defmacro defbuiltin(name, impl_name \\ nil) do
    impl = impl_name || name

    quote do
      def call(unquote(name), args, env) do
        {:ok, Alchemoo.Builtins.unquote(impl)(args), env}
      rescue
        e ->
          Logger.error("Error in builtin #{unquote(name)}: #{inspect(e)}")
          {:error, {:interpreter_error, e, __STACKTRACE__}}
      end
    end
  end
end
