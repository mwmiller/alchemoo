defmodule AlchemooTest do
  use ExUnit.Case
  doctest Alchemoo

  test "greets the world" do
    assert Alchemoo.hello() == :world
  end
end
