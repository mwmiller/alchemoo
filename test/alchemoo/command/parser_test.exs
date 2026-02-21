defmodule Alchemoo.Command.ParserTest do
  use ExUnit.Case, async: true

  alias Alchemoo.Command.Parser

  describe "parse/1" do
    test "parses single verb" do
      assert {:ok, %{verb: "look", dobj: nil, prep: nil, iobj: nil}} = Parser.parse("look")
    end

    test "parses verb with direct object" do
      assert {:ok, %{verb: "look", dobj: "me", prep: nil, iobj: nil}} = Parser.parse("look me")
    end

    test "parses verb with direct object and preposition" do
      assert {:ok, %{verb: "get", dobj: "ball", prep: "from", iobj: nil}} =
               Parser.parse("get ball from")
    end

    test "parses full command with all parts" do
      assert {:ok, %{verb: "put", dobj: "ball", prep: "in", iobj: "box"}} =
               Parser.parse("put ball in box")
    end

    test "handles extra words by ignoring them" do
      assert {:ok, %{verb: "give", dobj: "ball", prep: "to", iobj: "wizard"}} =
               Parser.parse("give ball to wizard please")
    end

    test "handles multiple spaces" do
      assert {:ok, %{verb: "look", dobj: "me", prep: nil, iobj: nil}} =
               Parser.parse("look   me")
    end

    test "handles leading/trailing spaces" do
      assert {:ok, %{verb: "look", dobj: nil, prep: nil, iobj: nil}} =
               Parser.parse("  look  ")
    end

    test "returns error for empty command" do
      assert {:error, :empty_command} = Parser.parse("")
    end

    test "returns error for whitespace-only command" do
      assert {:error, :empty_command} = Parser.parse("   ")
    end

    test "preserves case in verb and arguments" do
      assert {:ok, %{verb: "Look", dobj: "Me", prep: nil, iobj: nil}} = Parser.parse("Look Me")
    end
  end
end
