# frozen_string_literal: true

module QueryCostApm
  # Aggregator — collects and aggregates query results by fingerprint.
  #
  # Purpose: Collect individual query results from the Interceptor,
  # group them by fingerprint, calculate aggregate metrics (count, duration stats),
  # and provide rollup export functionality for periodic shipment to backend.
  #
  # Design:
  # - Stores metrics per fingerprint in-memory
  # - Thread-safe: uses a Mutex to protect shared state
  # - Tracks: count, total/min/max/avg duration, caller locations, timestamps
  # - Provides #rollup for periodic export
  # - Provides #clear to reset after export
  class Aggregator
    def initialize
      @lock = Mutex.new
      @aggregates = {}
    end

    # Add a single query result to the aggregator.
    # Groups by fingerprint and updates metrics.
    # Enforces a hard cap of 500 distinct fingerprints; overflow routes to "__OTHER_QUERIES__".
    #
    # @param result [Hash] — query result from Interceptor.process_query with:
    #   - :fingerprint_hash [String] — unique query fingerprint
    #   - :normalized_sql [String] — sanitized SQL
    #   - :duration_ms [Float] — query execution time
    #   - :caller_location [String] — application code location
    #
    # @return [void]
    def add_query_result(result)
      return if result.nil? || !result.is_a?(Hash)
      return if result[:fingerprint_hash].nil?

      hash = result[:fingerprint_hash]
      duration = result[:duration_ms].to_f
      sql = result[:normalized_sql]
      location = result[:caller_location]

      @lock.synchronize do
        # Determine target hash (may be overflow bucket if cap reached)
        target_hash = hash
        target_sql = sql

        # Check if this is a NEW fingerprint and we're at capacity
        if !@aggregates[hash] && @aggregates.length >= 500
          # Route overflow to __OTHER_QUERIES__
          target_hash = "__OTHER_QUERIES__"
          target_sql = "__OTHER_QUERIES__"
        end

        if @aggregates[target_hash]
          # Update existing aggregate
          agg = @aggregates[target_hash]
          agg[:count] += 1
          agg[:total_duration_ms] += duration
          agg[:min_duration_ms] = duration if duration < agg[:min_duration_ms]
          agg[:max_duration_ms] = duration if duration > agg[:max_duration_ms]
          agg[:caller_locations] << location unless agg[:caller_locations].include?(location)
          agg[:last_seen] = Time.now
        else
          # Create new aggregate
          @aggregates[target_hash] = {
            fingerprint_hash: target_hash,
            normalized_sql: target_sql,
            count: 1,
            total_duration_ms: duration,
            min_duration_ms: duration,
            max_duration_ms: duration,
            avg_duration_ms: duration,
            caller_locations: [location],
            first_seen: Time.now,
            last_seen: Time.now
          }
        end

        # Update avg_duration_ms
        agg = @aggregates[target_hash]
        agg[:avg_duration_ms] = agg[:total_duration_ms] / agg[:count]
      end
    end

    # Get a copy of all aggregates by fingerprint.
    #
    # @return [Hash] — map of fingerprint_hash => aggregate metrics
    def aggregates
      @lock.synchronize do
        @aggregates.dup
      end
    end

    # Clear all aggregates (typically after export).
    #
    # @return [void]
    def clear
      @lock.synchronize do
        @aggregates.clear
      end
    end

    # Generate a rollup for export.
    # Returns a structured hash with all aggregated metrics and summary.
    #
    # @return [Hash] with:
    #   - :timestamp [Time] — when the rollup was generated
    #   - :fingerprints [Array<Hash>] — array of aggregates
    #   - :summary [Hash] — rollup-level summary stats
    def rollup
      @lock.synchronize do
        fingerprints = @aggregates.values.map(&:dup)

        total_fingerprints = @aggregates.length
        total_queries = @aggregates.values.sum { |agg| agg[:count] }
        total_duration = @aggregates.values.sum { |agg| agg[:total_duration_ms] }

        {
          timestamp: Time.now,
          fingerprints: fingerprints,
          summary: {
            total_fingerprints: total_fingerprints,
            total_queries: total_queries,
            total_duration_ms: total_duration
          }
        }
      end
    end
  end
end
