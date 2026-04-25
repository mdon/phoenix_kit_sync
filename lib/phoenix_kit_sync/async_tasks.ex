defmodule PhoenixKitSync.AsyncTasks do
  @moduledoc """
  Spawn async tasks that need to outlive the calling process.

  Used by the admin LiveViews to fire HTTP notifications after a DB
  commit (status change, delete, etc.) — the DB transaction has already
  succeeded, so the remote site should learn about it even if the admin
  closes the tab. `Task.start_link/1` is wrong for this case because it
  cancels the task when the LV dies; a bare `Task.start/1` runs but with
  no supervision, so failures aren't logged and tasks accumulate on a
  hung HTTP timeout.

  `notify_remote_async/1` routes through `PhoenixKit.TaskSupervisor` (a
  named `Task.Supervisor` started by core `phoenix_kit`'s supervision
  tree) with `restart: :temporary`. If the supervisor isn't running —
  e.g. in a stripped-down test env — falls back to `Task.start/1` so the
  primary operation can still proceed.
  """

  @doc """
  Spawns `fun` as a fire-and-forget task supervised by
  `PhoenixKit.TaskSupervisor`. Returns `{:ok, pid}`.
  """
  @spec notify_remote_async((-> term())) :: {:ok, pid()} | {:error, term()}
  def notify_remote_async(fun) when is_function(fun, 0) do
    Task.Supervisor.start_child(PhoenixKit.TaskSupervisor, fun, restart: :temporary)
  catch
    :exit, _ -> Task.start(fun)
  end
end
