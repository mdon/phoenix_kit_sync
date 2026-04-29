defmodule PhoenixKitSync.Integration.IncomingPasswordTest do
  use PhoenixKitSync.DataCase, async: false

  # Pinning tests for `PhoenixKitSync.validate_incoming_password/1` after
  # the C12 fix: was using `==` on the stored vs provided password (timing
  # leak), now uses `Plug.Crypto.secure_compare/2` with `is_binary/1`
  # guards on both arguments. The same secure_compare flow is mirrored in
  # ApiController.validate_password/1 — both paths must agree.

  describe "validate_incoming_password/1" do
    test "returns true when no password is configured (mode = no_password)" do
      PhoenixKitSync.set_incoming_password(nil)
      assert PhoenixKitSync.validate_incoming_password("anything") == true
      assert PhoenixKitSync.validate_incoming_password(nil) == true
    end

    test "returns true on exact password match" do
      PhoenixKitSync.set_incoming_password("correct-horse-battery-staple")
      assert PhoenixKitSync.validate_incoming_password("correct-horse-battery-staple") == true
    end

    test "returns false on wrong password" do
      PhoenixKitSync.set_incoming_password("correct-horse-battery-staple")
      assert PhoenixKitSync.validate_incoming_password("wrong") == false
    end

    test "returns false when provided password is nil but a password is configured" do
      PhoenixKitSync.set_incoming_password("anything-non-empty")
      assert PhoenixKitSync.validate_incoming_password(nil) == false
    end

    test "returns false when provided password is non-binary (e.g. integer)" do
      PhoenixKitSync.set_incoming_password("anything-non-empty")
      assert PhoenixKitSync.validate_incoming_password(12_345) == false
    end
  end
end
