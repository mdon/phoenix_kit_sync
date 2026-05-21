defmodule PhoenixKitSync.ConnectionNotifier.RemoteUrlPrefixTest do
  # async: false — these tests mutate the :phoenix_kit_sync application env.
  use ExUnit.Case, async: false

  alias PhoenixKitSync.ConnectionNotifier

  # Regression coverage for issue #8: the notifier used to hardcode
  # "/phoenix_kit", 404'ing against remotes mounted under a different prefix.
  # It now derives the prefix from the local site's config (mirroring the
  # remote in symmetric deployments) with a global override, normalized.

  setup do
    original = Application.fetch_env(:phoenix_kit_sync, :remote_url_prefix)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:phoenix_kit_sync, :remote_url_prefix, value)
        :error -> Application.delete_env(:phoenix_kit_sync, :remote_url_prefix)
      end
    end)

    :ok
  end

  describe "remote_url_prefix/0 with an explicit override" do
    test "passes through a normal leading-slash prefix" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "/phoenix_kit")
      assert ConnectionNotifier.remote_url_prefix() == "/phoenix_kit"
    end

    test "treats empty string as no prefix" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "")
      assert ConnectionNotifier.remote_url_prefix() == ""
    end

    test "collapses a bare root prefix to no prefix (avoids // in the URL)" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "/")
      assert ConnectionNotifier.remote_url_prefix() == ""
    end

    test "adds a leading slash when the override omits it" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "custom")
      assert ConnectionNotifier.remote_url_prefix() == "/custom"
    end

    test "strips a trailing slash" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "/custom/")
      assert ConnectionNotifier.remote_url_prefix() == "/custom"
    end

    test "preserves multi-segment prefixes while stripping the trailing slash" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "/a/b/")
      assert ConnectionNotifier.remote_url_prefix() == "/a/b"
    end

    test "trims surrounding whitespace" do
      Application.put_env(:phoenix_kit_sync, :remote_url_prefix, "  /custom  ")
      assert ConnectionNotifier.remote_url_prefix() == "/custom"
    end
  end

  describe "remote_url_prefix/0 without an override" do
    test "mirrors the local PhoenixKit url prefix (default in the test env)" do
      Application.delete_env(:phoenix_kit_sync, :remote_url_prefix)
      assert ConnectionNotifier.remote_url_prefix() == PhoenixKit.Config.get_url_prefix()
    end
  end
end
