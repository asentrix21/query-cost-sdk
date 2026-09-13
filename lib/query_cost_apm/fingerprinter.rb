# frozen_string_literal: true

require "digest"

module QueryCostApm
  # Fingerprinter — takes sanitized SQL and produces a stable hash for aggregation.
  #
  # Purpose: Convert a sanitized SQL string into a canonical fingerprint
  # (hash + normalized SQL) that can be used as a key for grouping identical
  # query patterns.
  #
  # Design:
  # - Normalize whitespace and case (SQL keywords are case-insensitive)
  # - Hash using SHA256, truncated to 12 chars for brevity
  # - Return both the hash and normalized SQL for reference
  class Fingerprinter
    # Fingerprint — deterministically hash a sanitized SQL string.
    #
    # @param sql [String] sanitized SQL (already processed by Sanitizer)
    # @return [Hash] with keys:
    #   - :hash [String] — truncated SHA256 hex digest of the normalized SQL
    #   - :normalized_sql [String] — the input SQL normalized (trimmed, collapsed whitespace)
    def self.fingerprint(sql)
      return { hash: "", normalized_sql: "" } unless sql.is_a?(String)

      normalized = normalize_sql(sql)
      hash_value = compute_hash(normalized)

      {
        hash: hash_value,
        normalized_sql: normalized
      }
    end

    private

    # Normalize SQL for consistent hashing:
    # 1. Trim leading/trailing whitespace
    # 2. Collapse multiple spaces to single space
    # 3. Convert to lowercase (SQL keywords are case-insensitive)
    def self.normalize_sql(sql)
      sql.strip
         .gsub(/\s+/, " ")
         .downcase
    end

    # Compute a truncated SHA256 hash.
    # Full SHA256 hex is 64 chars; truncate to 12 for brevity while minimizing collisions.
    # 12 hex chars = 48 bits, giving us ~281 trillion possible hashes (extremely low collision risk).
    def self.compute_hash(normalized_sql)
      Digest::SHA256.hexdigest(normalized_sql)[0, 12]
    end
  end
end
