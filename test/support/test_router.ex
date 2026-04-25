defmodule PhoenixKitSync.Test.Router do
  @moduledoc """
  Minimal Router used by the LiveView test suite. Routes match the URLs
  produced by `PhoenixKitSync`'s admin_tabs so `live/2` calls in tests
  work with exactly the same URLs the LiveViews push themselves to.

  `PhoenixKit.Utils.Routes.path/1` defaults to no URL prefix when the
  `phoenix_kit_settings` table is empty; admin paths always get the
  default locale ("en") prefix.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {PhoenixKitSync.Test.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/en/admin", PhoenixKitSync.Web do
    pipe_through(:browser)

    live_session :sync_test,
      layout: {PhoenixKitSync.Test.Layouts, :app},
      on_mount: {PhoenixKitSync.Test.Hooks, :assign_scope} do
      live("/sync", Index, :index, as: :sync_index)
      live("/sync/connections", ConnectionsLive, :index, as: :sync_connections)
      live("/sync/connections/:action", ConnectionsLive, :index, as: :sync_connections_action)

      live("/sync/connections/:action/:id", ConnectionsLive, :index,
        as: :sync_connections_action_id
      )

      live("/sync/history", History, :index, as: :sync_history)
    end
  end
end
