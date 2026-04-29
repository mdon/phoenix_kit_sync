defmodule PhoenixKitSync.ConnCase do
  @moduledoc """
  Test case for controller-level tests against `Test.Endpoint` /
  `Test.Router`. Wires up `Phoenix.ConnTest`, an Ecto SQL sandbox
  connection, and the helpers from `PhoenixKitSync.LiveCase`.

  Use this for `ApiController` action tests and any other plug-pipeline
  tests that don't drive a LiveView.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      @endpoint PhoenixKitSync.Test.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import PhoenixKitSync.ActivityLogAssertions
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitSync.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end
end
