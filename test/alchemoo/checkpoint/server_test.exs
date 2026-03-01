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
      assert is_integer(info.etf_interval)
      assert is_integer(info.moo_interval)
      assert is_integer(info.keep_last_etf)
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

    test "rotates MOO exports without crashing" do
      # Stop the global server and start a custom one for this test
      if GenServer.whereis(Checkpoint) do
        Supervisor.terminate_child(Alchemoo.Supervisor, Checkpoint)
        Supervisor.delete_child(Alchemoo.Supervisor, Checkpoint)
      end

      # Load a database
      DB.load("test/fixtures/lambdacore.db")

      {:ok, _pid} =
        Checkpoint.start_link(
          checkpoint_dir: @test_dir,
          keep_last_moo: 2,
          moo_name: "RotationTest"
        )

      on_exit(fn ->
        # Restart the global one for other tests if it's missing
        if !GenServer.whereis(Checkpoint) do
          Supervisor.start_child(Alchemoo.Supervisor, {Checkpoint, []})
        end
      end)

      # Export 1
      {:ok, _} = Checkpoint.export_moo()
      Process.sleep(1100)

      # Export 2
      {:ok, _} = Checkpoint.export_moo()
      Process.sleep(1100)

      # Export 3 - should trigger cleanup
      {:ok, path3} = Checkpoint.export_moo()

      files =
        File.ls!(@test_dir)
        |> Enum.filter(&String.ends_with?(&1, ".db"))
        |> Enum.sort(:desc)

      # Should have kept 2 newest
      assert length(files) == 2
      assert Enum.member?(files, Path.basename(path3))
    end
  end
end
