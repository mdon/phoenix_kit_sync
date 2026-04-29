defmodule PhoenixKitSync.Test.Endpoint do
  @moduledoc """
  Minimal Phoenix.Endpoint used by the LiveView test suite.

  `phoenix_kit_sync` is a library — in production it borrows the host
  app's endpoint and router. For tests we spin up a tiny endpoint +
  router (`PhoenixKitSync.Test.Router`) so `Phoenix.LiveViewTest` can
  drive our LiveViews through `live/2` with real URLs.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_kit_sync

  @session_options [
    store: :cookie,
    key: "_phoenix_kit_sync_test_key",
    signing_salt: "sync-test-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Real cross-site sync flows POST JSON bodies; the parser is needed
  # so ApiController gets `params` populated when ConnectionNotifier
  # hits us.
  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.Session, @session_options)
  plug(PhoenixKitSync.Test.Router)
end
