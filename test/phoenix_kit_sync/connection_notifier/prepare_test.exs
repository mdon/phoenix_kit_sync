defmodule PhoenixKitSync.ConnectionNotifier.PrepareTest do
  use ExUnit.Case, async: true

  alias PhoenixKitSync.ConnectionNotifier.Prepare

  # Pinning tests for the column-scoped decimal coercion fix from PR #2
  # follow-up. Pre-fix, `prepare_value/1` ran the broad
  # `~r/^-?\d+\.\d+$/` regex on every binary value — a "3.14" in a text
  # column (a version number, a measurement label) would silently become
  # `%Decimal{}` and trip Postgrex when bound to a non-numeric column.
  # The 3-arity `value/3` accepts the column name + a list of numeric
  # column names and only invokes the regex when the column is on the
  # list.

  describe "value/3 — decimal coercion is column-scoped" do
    test "coerces decimal-shaped strings on numeric columns" do
      result = Prepare.value("3.14", "price", ["price"])
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("3.14"))
    end

    test "leaves decimal-shaped strings as strings on non-numeric columns" do
      # Version numbers like "3.14" must stay as strings on text columns
      # — this is the actual regression scenario the fix targeted.
      assert Prepare.value("3.14", "version", ["price", "amount"]) == "3.14"
    end

    test "coerces on multi-numeric-column list" do
      assert %Decimal{} = Prepare.value("99.99", "amount", ["price", "amount", "tax_rate"])
    end

    test "ISO datetime strings still parse regardless of column type" do
      # ISO formats (datetime/date/time) are unambiguous — they're parsed
      # by shape, not by column type, so the column scoping doesn't
      # affect them.
      assert %DateTime{} = Prepare.value("2026-04-25T12:34:56Z", "created_at", [])
      assert %Date{} = Prepare.value("2026-04-25", "birthday", [])
    end

    test "non-binary values pass through unchanged" do
      assert Prepare.value(42, "amount", ["amount"]) == 42
      assert Prepare.value(true, "active", []) == true
      assert Prepare.value(nil, "anything", []) == nil
    end

    test "empty numeric_cols list disables coercion entirely" do
      assert Prepare.value("3.14", "anything", []) == "3.14"
    end
  end

  describe "value/1 — broad coercion (PK / unique-column lookup paths)" do
    # The 1-arity form is kept for `check_pk_exists` /
    # `find_match_by_unique`, where the values are known PKs / unique-key
    # values rather than free-text — broad coercion is fine there.
    test "coerces decimal-shaped strings unconditionally" do
      assert %Decimal{} = Prepare.value("3.14")
    end

    test "leaves non-decimal binaries unchanged" do
      assert Prepare.value("just text") == "just text"
    end
  end

  describe "numeric_columns/1" do
    test "returns empty list for unknown table (safe fallback)" do
      assert Prepare.numeric_columns("definitely_not_a_real_table_aaaaa") == []
    end
  end
end
