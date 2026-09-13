# frozen_string_literal: true

require "spec_helper"
require "query_cost_apm/sanitizer"

RSpec.describe QueryCostApm::Sanitizer do
  describe ".sanitize" do
    # Case 1: Baseline case from the design doc
    it "case 1: baseline with numbers and strings" do
      input = "SELECT * FROM payments WHERE amount > 500.00 AND status = 'COMPLETED'"
      expected = "SELECT * FROM payments WHERE amount > ? AND status = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 2: IN-list collapse
    it "case 2: IN-list with numeric values" do
      input = "SELECT * FROM users WHERE id IN (1, 2, 3)"
      expected = "SELECT * FROM users WHERE id IN (?)"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 3: IN-list with strings
    it "case 3: IN-list with string values" do
      input = "SELECT * FROM users WHERE status IN ('A', 'B', 'C')"
      expected = "SELECT * FROM users WHERE status IN (?)"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 4: Negative number
    it "case 4: negative number" do
      input = "WHERE balance < -100"
      expected = "WHERE balance < ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 5: Decimal number
    it "case 5: decimal number" do
      input = "WHERE score = 3.14"
      expected = "WHERE score = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 6: Escaped quote inside string literal
    it "case 6: escaped quote inside string literal" do
      input = "WHERE name = 'O''Brien'"
      expected = "WHERE name = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 7: LIKE pattern (still just a string literal)
    it "case 7: LIKE pattern with string literal" do
      input = "WHERE email LIKE '%@gmail.com'"
      expected = "WHERE email LIKE ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 8: UUID (quoted string, no special-casing needed)
    it "case 8: UUID as quoted string" do
      input = "WHERE id = '550e8400-e29b-41d4-a716-446655440000'"
      expected = "WHERE id = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 9: Postgres cast syntax — literal replaced, cast preserved
    it "case 9: Postgres cast syntax" do
      input = "WHERE created_at > '2024-01-01'::timestamp"
      expected = "WHERE created_at > ?::timestamp"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 10: Bare boolean literal
    it "case 10: bare boolean literal (true)" do
      input = "WHERE active = true"
      expected = "WHERE active = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 11: NULL in IS NULL (must NOT be replaced, only = NULL would be)
    it "case 11: IS NULL must not replace NULL keyword" do
      input = "WHERE deleted_at IS NULL"
      expected = "WHERE deleted_at IS NULL"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 12: Digits inside an identifier must survive
    it "case 12: digits inside identifier must survive" do
      input = "SELECT * FROM table_2024 WHERE col1 = 5"
      expected = "SELECT * FROM table_2024 WHERE col1 = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 13: JSON operator column access
    it "case 13: JSON operator column access" do
      input = "WHERE data->>'ssn' = '123-45-6789'"
      # Note: the key 'ssn' is also technically a quoted string literal and gets replaced with ?.
      # This is an accepted "over-scrub" in the safe direction (per design doc §5.2):
      # it preserves operator structure but replaces the key name with a placeholder.
      # This is safer than trying to distinguish between JSON keys and value literals.
      expected = "WHERE data->>? = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 14: Postgres double-quoted identifiers must NOT be touched
    it "case 14: double-quoted identifiers untouched" do
      input = "SELECT \"user_id\" FROM users WHERE \"user_id\" = 5"
      expected = "SELECT \"user_id\" FROM users WHERE \"user_id\" = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 15: Multi-statement rejection
    it "case 15: multi-statement SQL rejected with nil" do
      input = "SELECT 1; DROP TABLE users;"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to be_nil
    end

    # Case 16: Empty IN-list edge case
    it "case 16: empty IN-list" do
      input = "SELECT * FROM users WHERE id IN ()"
      expected = "SELECT * FROM users WHERE id IN ()"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 17: Separated-bind-params path (template passed through untouched)
    it "case 17: separated bind params — template unchanged, binds never read" do
      input = "WHERE id = $1"
      binds = [mock_bind_object(123)]
      expected = "WHERE id = $1"
      result = QueryCostApm::Sanitizer.sanitize(input, binds)
      expect(result).to eq(expected)
    end

    # Case 18: Whitespace normalization
    it "case 18: irregular whitespace normalized" do
      input = "  SELECT   *   FROM  users  "
      expected = "SELECT * FROM users"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 19: Semicolon inside a string literal should not trigger multi-statement rejection
    it "case 19: semicolon inside string literal does not trigger multi-statement rejection" do
      input = "WHERE notes = 'contains a ; semicolon but only one statement'"
      expected = "WHERE notes = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Case 20: Comment-like text inside a string literal
    it "case 20: comment-like text inside string literal not stripped" do
      input = "SELECT * FROM logs WHERE msg = '/* not a real comment */'"
      expected = "SELECT * FROM logs WHERE msg = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Extra edge case: multiple consecutive escaped quotes
    it "case 21: multiple consecutive escaped quotes" do
      input = "WHERE name = 'O''Brien''s'"
      expected = "WHERE name = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Extra edge case: double-quote (Postgres identifier) not treated as string literal
    it "case 22: double-quoted identifiers stay intact" do
      input = 'WHERE "value" = 5'
      expected = 'WHERE "value" = ?'
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end

    # Extra edge case: numeric literal at start of SQL
    it "case 23: numeric literal at start" do
      input = "123 WHERE id = 5"
      expected = "? WHERE id = ?"
      result = QueryCostApm::Sanitizer.sanitize(input)
      expect(result).to eq(expected)
    end
  end

  # Helper for case 17
  def mock_bind_object(value)
    double("bind", value: value)
  end
end
