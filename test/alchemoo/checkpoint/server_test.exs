defmodule Alchemoo.Checkpoint.ServerTest do
  use ExUnit.Case, async: false

  alias Alchemoo.Checkpoint.Server, as: Checkpoint
  alias Alchemoo.Database.Server, as: DB

  @test_dir "test/state/checkpoints"

  setup do
    # Clean test directory
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  describe "checkpoint/0" do
    test "creates checkpoint file" do
      # Load a database first
      DB.load("test/fixtures/lambdacore.db")

      # Create checkpoint
      assert {:ok, filename} = Checkpoint.checkpoint()
      assert String.starts_with?(filename, "checkpoint-")
      assert String.ends_with?(filename, ".etf")

      # Check file exists
      info = Checkpoint.info()
      path = Path.join(info.checkpoint_dir, filename)
      assert File.exists?(path)
    end
  end

  describe "list_checkpoints/0" do
    test "lists available checkpoints" do
      DB.load("test/fixtures/lambdacore.db")

      # Create a few checkpoints
      {:ok, _} = Checkpoint.checkpoint()
      Process.sleep(100)
      {:ok, _} = Checkpoint.checkpoint()

      # List them
      checkpoints = Checkpoint.list_checkpoints()
      assert length(checkpoints) >= 2
      assert Enum.all?(checkpoints, &String.starts_with?(&1, "checkpoint-"))
    end
  end

  describe "info/0" do
    test "returns checkpoint server info" do
      info = Checkpoint.info()

      assert is_binary(info.checkpoint_dir)
      assert is_integer(info.interval)
      assert is_integer(info.keep_last)
      assert is_integer(info.checkpoint_count)
    end
  end

  describe "export_moo/1" do
    test "exports database to MOO format" do
      # Load a database
      DB.load("test/fixtures/lambdacore.db")

      # Export to MOO format
      export_path = Path.join(@test_dir, "export.db")
      assert {:ok, ^export_path} = Checkpoint.export_moo(export_path)

      # Check file exists and has content
      assert File.exists?(export_path)
      content = File.read!(export_path)

      # Check MOO format header
      assert content =~ "** LambdaMOO Database, Format Version 4 **"
      assert content =~ "** Exported by Alchemoo **"

      # Check has objects
      assert content =~ "#0"
    end
  end
end
