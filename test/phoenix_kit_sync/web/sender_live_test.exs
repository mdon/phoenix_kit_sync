defmodule PhoenixKitSync.Web.SenderLiveTest do
  use PhoenixKitSync.LiveCase

  # Sender LV isn't routed in the test router (production reaches it via
  # a different entry point inside the connections flow), so these tests
  # exercise the unit behaviour around the PID → UUIDv7 token refactor
  # from PR #1 follow-up. The full LV smoke is covered manually + by the
  # browser diff in C0/final-checklist.

  describe "receiver token round-trip (PR #1 fix)" do
    # The fix: `string_to_pid/1` and `pid_to_string/1` were deleted; the
    # disconnect button now carries `phx-value-token` keyed to a stable
    # `UUIDv7.generate()` token stored inside `receiver_data`. The pin
    # tests are inside the `Web.Sender` private function lookups via
    # public `find_receiver_by_token/2` not being exposed — the next
    # closest pin is verifying the data shape `:token` field is a UUIDv7
    # string. This test instead asserts the deletions actually
    # happened — failing on revert if either function returns.
    test "string_to_pid / pid_to_string are no longer defined on Sender" do
      refute function_exported?(PhoenixKitSync.Web.Sender, :string_to_pid, 1)
      refute function_exported?(PhoenixKitSync.Web.Sender, :pid_to_string, 1)
    end
  end
end
