defmodule Alchemoo.Command.ParserTest do
  use ExUnit.Case, async: true

  alias Alchemoo.Command.Parser

  describe "parse/1" do
    test "parses single verb" do
      assert {:ok, %{verb: "look", dobj: "", prep: -1, iobj: ""}} = Parser.parse("look")
    end

    test "parses verb with direct object" do
      assert {:ok, %{verb: "look", dobj: "me", prep: -1, iobj: ""}} = Parser.parse("look me")
    end

    test "parses verb with direct object and preposition" do
      # "at" is index 1
      assert {:ok, %{verb: "look", dobj: "ball", prep: 1, iobj: ""}} =
               Parser.parse("look ball at")
    end

    test "parses full command with all parts" do
      # "in" is index 3
      assert {:ok, %{verb: "put", dobj: "ball", prep: 3, iobj: "box"}} =
               Parser.parse("put ball in box")
    end

    test "parses command with multi-word preposition" do
      # "in front of" is index 2
      assert {:ok, %{verb: "drop", dobj: "ball", prep: 2, iobj: "house"}} =
               Parser.parse("drop ball in front of house")
    end

    test "handles complex dobj and iobj" do
      # "to" is index 1
      assert {:ok, %{verb: "give", dobj: "the big blue ball", prep: 1, iobj: "the tall wizard"}} =
               Parser.parse("give the big blue ball to the tall wizard")
    end

    test "handles multiple spaces" do
      assert {:ok, %{verb: "look", dobj: "me", prep: -1, iobj: ""}} =
               Parser.parse("look   me")
    end

    test "returns error for empty command" do
      assert {:error, :empty_command} = Parser.parse("")
    end

    test "returns error for whitespace-only command" do
      assert {:error, :empty_command} = Parser.parse("   ")
    end

    test "preserves case in objects but verb name is as-is" do
      # Parser currently does not downcase verb, Executor/Resolver do case-insensitive match
      assert {:ok, %{verb: "Look", dobj: "the Ball", prep: 1, iobj: "Me"}} =
               Parser.parse("Look the Ball at Me")
    end
  end
end
