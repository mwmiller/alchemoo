defmodule Alchemoo.TaskTest do
  use ExUnit.Case, async: false

  alias Alchemoo.{Database, Runtime, Task, TaskSupervisor}

  describe "run/3" do
    test "executes simple verb code" do
      code = "return 10 + 20;"
      assert {:ok, {:num, 30}} = Task.run(code, %{})
    end

    test "enforces tick quota" do
      # Loop enough to exceed a small quota
      code = """
      while (1)
        # busy loop
      endwhile
      """

      # We call MOOTask.run directly and expect it to return an error when quota is hit
      runtime = Runtime.new(Database.Server.get_snapshot())
      env = %{:runtime => runtime}
      opts = [tick_quota: 100]

      assert {:error, :E_QUOTA} = Task.run(code, env, opts)
    end
  end

  describe "TaskSupervisor" do
    test "spawns and kills tasks" do
      # Use suspend to ensure the task stays alive long enough to be killed
      code = "suspend(600); return 42;"

      {:ok, pid} = TaskSupervisor.spawn_task(code, %{})
      ref = Process.monitor(pid)

      # Ensure it's registered
      Process.sleep(211)
      assert TaskSupervisor.count_tasks() > 0

      assert :ok = TaskSupervisor.kill_task(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1009
    end
  end
end
