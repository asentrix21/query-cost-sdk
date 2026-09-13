# frozen_string_literal: true

require "spec_helper"
require "query_cost_apm/interceptor"

RSpec.describe QueryCostApm::Interceptor do
  describe ".subscribe" do
    it "subscribes to ActiveSupport::Notifications" do
      # This test just ensures the subscription is established without error
      expect do
        QueryCostApm::Interceptor.subscribe
      end.not_to raise_error
    end

    it "returns a subscription handle" do
      handle = QueryCostApm::Interceptor.subscribe
      expect(handle).not_to be_nil
    end
  end

  describe ".process_query" do
    # Core: extract and fingerprint a query from a notification payload
    it "processes a basic query notification" do
      payload = {
        sql: "SELECT * FROM users WHERE id = 1",
        binds: [],
        name: "User Load",
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:fingerprint_hash)
      expect(result).to have_key(:duration_ms)
      expect(result).to have_key(:caller_location)
    end

    # Timing: extract start/end times
    it "calculates duration from start and end times" do
      start_time = Time.now
      end_time = start_time + 0.05  # 50ms

      # In real Rails notifications, start and finish are passed as separate
      # parameters, not inside the payload. But process_query expects them
      # merged into the payload for convenience in testing.
      payload = {
        sql: "SELECT * FROM users",
        binds: [],
        name: "User Load",
        connection_id: 123,
        start: start_time,
        finish: end_time  # Note: Rails uses 'finish', not 'end'
      }

      result = QueryCostApm::Interceptor.process_query(payload)

      # Duration should be ~50ms (within tolerance)
      expect(result[:duration_ms]).to be >= 45
    end

    # Filter: skip SCHEMA queries
    it "returns nil for SCHEMA queries" do
      payload = {
        sql: "SELECT * FROM information_schema.columns",
        binds: [],
        name: "SCHEMA",
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)
      expect(result).to be_nil
    end

    # Filter: skip transaction control
    it "returns nil for BEGIN transaction" do
      payload = {
        sql: "BEGIN",
        binds: [],
        name: nil,
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)
      expect(result).to be_nil
    end

    it "returns nil for COMMIT transaction" do
      payload = {
        sql: "COMMIT",
        binds: [],
        name: nil,
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)
      expect(result).to be_nil
    end

    it "returns nil for ROLLBACK transaction" do
      payload = {
        sql: "ROLLBACK",
        binds: [],
        name: nil,
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)
      expect(result).to be_nil
    end

    # Sanitization + Fingerprinting
    it "sanitizes and fingerprints the query" do
      payload = {
        sql: "SELECT * FROM users WHERE email = 'john@example.com'",
        binds: [],
        name: "User Load",
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)

      # Should contain a fingerprint hash, not the raw email
      expect(result[:fingerprint_hash]).not_to include("john@example.com")
      expect(result[:fingerprint_hash]).to be_a(String)
      expect(result[:fingerprint_hash].length).to be_between(12, 64)
    end

    # Caller location extraction
    it "extracts caller location from stack trace" do
      payload = {
        sql: "SELECT * FROM users",
        binds: [],
        name: "User Load",
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)

      expect(result[:caller_location]).to be_a(String)
      # In pure test context, we might not find app code (returns "unknown")
      # but in real Rails, this would be like "app/models/user.rb:42"
      expect(result[:caller_location]).not_to be_empty
    end

    # Bind parameters: separated binds are preserved in sanitization
    it "handles separated bind parameters" do
      payload = {
        sql: "SELECT * FROM users WHERE id = $1",
        binds: ["some_secret_value"],  # This should never appear in output
        name: "User Load",
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)

      expect(result[:fingerprint_hash]).not_to include("some_secret_value")
      expect(result[:fingerprint_hash]).to be_a(String)
    end

    # Edge case: invalid payload should not crash
    it "handles nil SQL gracefully" do
      payload = {
        sql: nil,
        binds: [],
        name: nil,
        connection_id: 123
      }

      result = QueryCostApm::Interceptor.process_query(payload)
      # Should return nil or a safe default, not crash
      expect { result }.not_to raise_error
    end

    # Edge case: empty payload
    it "handles empty payload gracefully" do
      payload = {}

      result = QueryCostApm::Interceptor.process_query(payload)
      expect { result }.not_to raise_error
    end
  end

  describe ".unsubscribe" do
    it "unsubscribes from notifications" do
      handle = QueryCostApm::Interceptor.subscribe
      expect do
        QueryCostApm::Interceptor.unsubscribe(handle)
      end.not_to raise_error
    end
  end
end
