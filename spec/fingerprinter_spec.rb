# frozen_string_literal: true

require "spec_helper"
require "query_cost_apm/fingerprinter"

RSpec.describe QueryCostApm::Fingerprinter do
  describe ".fingerprint" do
    # Core behavior: same SQL → same hash
    it "produces the same hash for identical sanitized SQL" do
      sql = "SELECT * FROM users WHERE id = ?"
      result1 = QueryCostApm::Fingerprinter.fingerprint(sql)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result1[:hash]).to eq(result2[:hash])
      expect(result1[:normalized_sql]).to eq(result2[:normalized_sql])
    end

    # Core behavior: different SQL → different hashes
    it "produces different hashes for different SQL" do
      sql1 = "SELECT * FROM users WHERE id = ?"
      sql2 = "SELECT * FROM users WHERE email = ?"

      result1 = QueryCostApm::Fingerprinter.fingerprint(sql1)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql2)

      expect(result1[:hash]).not_to eq(result2[:hash])
    end

    # SQL with whitespace variations should produce same hash
    # (normalization already happened in sanitizer, but defensive)
    it "handles extra whitespace consistently" do
      sql1 = "SELECT * FROM users WHERE id = ?"
      sql2 = "SELECT  *  FROM  users  WHERE  id  =  ?"

      result1 = QueryCostApm::Fingerprinter.fingerprint(sql1)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql2)

      expect(result1[:hash]).to eq(result2[:hash])
    end

    # Return value structure
    it "returns a hash with :hash and :normalized_sql keys" do
      sql = "SELECT * FROM users WHERE id = ?"
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result).to have_key(:hash)
      expect(result).to have_key(:normalized_sql)
      expect(result[:hash]).to be_a(String)
      expect(result[:normalized_sql]).to be_a(String)
    end

    # Hash should be a reasonable size (truncated SHA256, not full)
    it "produces a hash that is a reasonable length" do
      sql = "SELECT * FROM users WHERE id = ?"
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      # SHA256 in hex is 64 chars; we truncate for brevity
      # Expect between 12 and 64 chars (a truncated SHA256)
      expect(result[:hash].length).to be_between(12, 64)
    end

    # Normalized SQL should be clean
    it "returns normalized SQL without leading/trailing whitespace" do
      sql = "  SELECT * FROM users WHERE id = ?  "
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result[:normalized_sql]).to eq("select * from users where id = ?")
    end

    # Case sensitivity: SQL keywords are typically case-insensitive
    it "treats SQL keywords case-insensitively for hashing" do
      sql1 = "SELECT * FROM users WHERE id = ?"
      sql2 = "select * from users where id = ?"

      result1 = QueryCostApm::Fingerprinter.fingerprint(sql1)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql2)

      expect(result1[:hash]).to eq(result2[:hash])
    end

    # Deterministic: same input always produces same output
    it "is deterministic across multiple calls" do
      sql = "SELECT * FROM orders WHERE total > ? AND status = ?"
      hashes = 10.times.map { QueryCostApm::Fingerprinter.fingerprint(sql)[:hash] }

      expect(hashes.uniq.length).to eq(1)
    end

    # Real-world examples
    it "handles complex queries correctly" do
      sql = "SELECT * FROM payments WHERE amount > ? AND status IN (?) AND created_at > ?::timestamp"
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result[:hash]).to be_a(String)
      expect(result[:normalized_sql]).to include("payments")
      expect(result[:normalized_sql]).not_to be_empty
    end

    # Edge case: very short query
    it "handles very short queries" do
      sql = "SELECT 1"
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result[:hash]).to be_a(String)
      expect(result[:normalized_sql]).to eq("select 1")
    end

    # Edge case: empty string (shouldn't happen, but defensive)
    it "handles empty string (edge case)" do
      sql = ""
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result).to have_key(:hash)
      expect(result[:hash]).to be_a(String)
    end

    # Multiple spaces collapse to one
    it "collapses multiple spaces in normalized SQL" do
      sql = "SELECT    *    FROM    users"
      result = QueryCostApm::Fingerprinter.fingerprint(sql)

      expect(result[:normalized_sql]).to eq("select * from users")
    end

    # Semantically different but structurally similar queries have different hashes
    it "distinguishes between SELECT and DELETE" do
      sql1 = "SELECT * FROM users WHERE id = ?"
      sql2 = "DELETE FROM users WHERE id = ?"

      result1 = QueryCostApm::Fingerprinter.fingerprint(sql1)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql2)

      expect(result1[:hash]).not_to eq(result2[:hash])
    end

    # Order matters: WHERE vs UPDATE
    it "distinguishes between WHERE clause differences" do
      sql1 = "SELECT * FROM users WHERE id = ? AND email = ?"
      sql2 = "SELECT * FROM users WHERE email = ? AND id = ?"

      result1 = QueryCostApm::Fingerprinter.fingerprint(sql1)
      result2 = QueryCostApm::Fingerprinter.fingerprint(sql2)

      # Different order = different query (even if semantically equivalent)
      expect(result1[:hash]).not_to eq(result2[:hash])
    end
  end
end
