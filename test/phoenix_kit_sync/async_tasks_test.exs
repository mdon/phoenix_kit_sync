defmodule PhoenixKitSync.AsyncTasksTest do
  use ExUnit.Case, async: false

  alias PhoenixKitSync.AsyncTasks

  # Pinning test for the supervised vs linked task distinction. Before
  # the fix, every async notification was bare `Task.start/1` — orphan
  # processes could pile up on a hung HTTP timeout. The fix routes
  # through `PhoenixKit.TaskSupervisor` with `restart: :temporary`. The
  # test starts a task that blocks on `receive`, then verifies the task
  # PID shows up in `Task.Supervisor.children/1` — proving it's
  # registered with the supervisor and not a bare unsupervised process.

  test "notify_remote_async/1 spawns a child of PhoenixKit.TaskSupervisor" do
    parent = self()
    ref = make_ref()

    {:ok, task_pid} =
      AsyncTasks.notify_remote_async(fn ->
        send(parent, {:started, ref, self()})

        receive do
          {:done, ^ref} -> :ok
        after
          2_000 -> :timeout
        end
      end)

    assert_receive {:started, ^ref, ^task_pid}, 1_000

    children = Task.Supervisor.children(PhoenixKit.TaskSupervisor)

    assert task_pid in children,
           "expected task #{inspect(task_pid)} to be a child of PhoenixKit.TaskSupervisor; " <>
             "children=#{inspect(children)}"

    # Cleanup: unblock the task so it terminates.
    send(task_pid, {:done, ref})
  end

  test "notify_remote_async/1 returns {:ok, pid} on the supervised path" do
    {:ok, pid} = AsyncTasks.notify_remote_async(fn -> :ok end)
    assert is_pid(pid)
  end
end
