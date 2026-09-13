# frozen_string_literal: true

module QueryCostApm
  # Sanitizer — highest-risk, defense-in-depth component.
  # Removes or replaces literal values from SQL to create a fingerprint-safe
  # canonical query shape. Never reads bind parameter VALUES if provided.
  #
  # Processing order is critical and specified explicitly (§1.2 of the design doc):
  # 1. Reject multi-statement input outright (return nil if > 1 statement)
  # 2. If binds present, skip to step 5 (whitespace normalization)
  # 3. Replace quoted string literals with ?
  # 4. Replace bare literals (numbers, booleans, NULL in specific contexts)
  # 5. Collapse IN (...) lists to IN (?)
  # 6. Normalize whitespace
  class Sanitizer
    # Sanitize raw SQL into a fingerprint-safe canonical form.
    #
    # @param sql [String] raw SQL text, possibly with interpolated values or templates
    # @param binds [Array, nil] if present and non-empty, sql is already a parameterized
    #        template and binds are NEVER read/output — only checked for presence.
    #        This enables safe handling of driver-separated bind parameters (Rails ActiveRecord).
    #
    # @return [String] sanitized/normalized SQL, or nil if input should be dropped
    #         (e.g., multi-statement queries)
    def self.sanitize(sql, binds = nil)
      return nil unless sql.is_a?(String)

      sql = sql.dup

      # Step 2: If binds is present and non-empty, sql is already a template.
      # Skip to step 6 (whitespace normalization) and return early.
      # Do this FIRST so we don't try to parse a template as raw SQL.
      if binds.is_a?(Array) && binds.any?
        return normalize_whitespace(sql)
      end

      # Step 3: Replace quoted string literals (including escaped single quotes).
      # Regex: matches 'anything' where 'anything' can include '' (escaped quote).
      # Pattern: '([^']|'')*' — either non-quote chars or pairs of quotes.
      sql.gsub!(/'([^']|'')*'/, "?")

      # Step 1: Reject multi-statement input outright.
      # NOW safe to check because string literals (which might contain semicolons) are gone.
      # Check for ';' followed by non-whitespace (indicating another statement).
      if sql.match?(/;\s*\S/)
        return nil
      end

      # Step 4: Replace bare literals — numeric and boolean keywords.
      # Numeric: -?N.N or -?N (with word boundaries to avoid table_2024 → table_?)
      # Must use \b word boundary or (?<!\w) negative lookbehind to avoid partial matches.
      sql.gsub!(/(?<!\w)-?\d+\.?\d*(?!\w)/, "?")

      # Booleans: true, false (case-insensitive)
      sql.gsub!(/\b(true|false)\b/i, "?")

      # NULL: only replace in specific contexts, not in IS NULL.
      # Replace NULL only when it matches (,\s*NULL|=\s*NULL).
      sql.gsub!(/=\s*NULL\b/i, "= ?")

      # Step 5: Collapse IN lists.
      # After steps 3-4, any IN (val1, val2, val3) has become IN (?, ?, ?).
      # Collapse that pattern to IN (?).
      # Pattern: IN followed by optional whitespace, (, optional ws, ?, (optional ws, comma, ws, ?)*,
      # optional ws, ).
      sql.gsub!(/IN\s*\(\s*\?\s*(?:,\s*\?)*\s*\)/i, "IN (?)")

      # Step 6: Normalize whitespace.
      normalize_whitespace(sql)
    end

    private

    # Normalize whitespace: collapse multiple spaces to one, trim.
    def self.normalize_whitespace(sql)
      sql.strip.gsub(/\s+/, " ")
    end
  end
end
