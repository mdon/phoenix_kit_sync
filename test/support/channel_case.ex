defmodule PhoenixKitSync.ChannelCase do
  @moduledoc """
  Test case for Phoenix Channel + Socket tests via
  `Phoenix.ChannelTest`.

  Use this for tests against `PhoenixKitSync.Web.SyncSocket` and
  `PhoenixKitSync.Web.SyncChannel` — exercises the ephemeral
  code-based protocol end-to-end without a real WebSocket connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      @endpoint PhoenixKitSync.Test.Endpoint

      use Phoenix.ChannelTest
      import PhoenixKitSync.ActivityLogAssertions
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitSync.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
