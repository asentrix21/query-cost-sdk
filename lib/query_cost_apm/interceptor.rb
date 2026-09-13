# frozen_string_literal: true

require "active_support/notifications"

module QueryCostApm
  # Interceptor — hooks into Rails' query notification system.
  #
  # Purpose: Capture database queries as they execute, extract timing/metadata,
  # sanitize, fingerprint, and pass to the aggregator.
  #
  # Design:
  # - Subscribes to "sql.active_record" notifications (Rails ActiveSupport::Notifications)
  # - Filters out non-application queries (SCHEMA, transaction control, migrations)
  # - Never blocks the application request path (all work is synchronous but fast)
  # - Wraps entire flow in exception handling (fail-open design)
  # - Extracts caller location for attribution (without using it as aggregation key)
  class Interceptor
    @subscription_handle = nil

    # Subscribe to ActiveSupport::Notifications for SQL queries.
    # Callback fires synchronously, so must be fast.
    # @param on_result [Proc, nil] optional callback invoked with each non-nil result of
    #        process_query. This is the seam the Phase 4 Aggregator will plug into
    #        (subscribe { |result| Aggregator.record(result) }); it also lets tests observe
    #        real results without calling process_query from outside this file, which would
    #        introduce a stack frame the path-exclusion filter can't distinguish from real
    #        application code.
    def self.subscribe(&on_result)
      @subscription_handle = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, start, finish, _id, payload|
        begin
          result = process_query(payload.merge(start: start, finish: finish))
          on_result.call(result) if on_result && result
        rescue StandardError => e
          # Fail open: log at debug level only, never raise into the host app
          # This prevents a sanitizer or fingerprinter bug from crashing the application
          warn("[QueryCostApm] Error processing query: #{e.message}") if ENV["QUERY_COST_APM_DEBUG"]
        end
      end

      @subscription_handle
    end

    # Unsubscribe from notifications.
    def self.unsubscribe(handle)
      ActiveSupport::Notifications.unsubscribe(handle) if handle
    end

    # Process a single query notification.
    # Returns a Hash with fingerprinting and timing info, or nil if query should be skipped.
    #
    # @param payload [Hash] — Rails notification payload with:
    #   - :sql [String] — the SQL query
    #   - :binds [Array] — bind parameters (values, not template)
    #   - :name [String] — query type annotation
    #   - :connection_id [Integer] — database connection ID
    #   - :start [Time] — query start time
    #   - :finish [Time] — query finish time
    #
    # @return [Hash, nil] — fingerprint and timing info, or nil if filtered out
    def self.process_query(payload)
      return nil unless payload.is_a?(Hash)

      sql = payload[:sql]
      return nil unless sql.is_a?(String) && !sql.empty?

      # Filter: skip SCHEMA queries
      return nil if payload[:name] == "SCHEMA"

      # Filter: skip transaction control statements
      sql_upper = sql.strip.upcase
      return nil if sql_upper.match?(/\A(BEGIN|COMMIT|ROLLBACK)(\s|;|\z)/)

      # Calculate duration
      start_time = payload[:start]
      finish_time = payload[:finish]
      duration_ms = if start_time && finish_time
                      ((finish_time - start_time) * 1000).round(2)
                    else
                      0.0
                    end

      # Sanitize and fingerprint
      binds = payload[:binds]
      sanitized_sql = Sanitizer.sanitize(sql, binds)
      return nil unless sanitized_sql

      fingerprint_result = Fingerprinter.fingerprint(sanitized_sql)

      # Extract caller location (application code frame)
      caller_location = extract_caller_location

      {
        fingerprint_hash: fingerprint_result[:hash],
        normalized_sql: fingerprint_result[:normalized_sql],
        duration_ms: duration_ms,
        caller_location: caller_location,
        binds_count: binds.is_a?(Array) ? binds.length : 0
      }
    end

    private

    # Extract the first application code frame from the call stack.
    # Skips frames from:
    # - This gem's own code (query_cost_apm)
    # - Rails internals (activerecord, activesupport, actionpack)
    # - Ruby internals
    #
    # Returns a string like "app/models/user.rb:42:in `find_by_email'" or "spec/support/factories.rb:10"
    def self.extract_caller_location
      # Get the current call stack
      # Each entry is like: "/path/to/app/models/user.rb:42:in `method_name'"
      caller_frames = caller_locations(1, 25)  # Skip frame 0 (this method itself), get next 25 — filter handles the rest

      # Find the first frame that's not from this gem, not from Rails, not from ruby internals
      frame = caller_frames.find do |loc|
        path = loc.path
        !path.include?("query_cost_apm") &&
          !path.include?("activerecord") &&
          !path.include?("activesupport") &&
          !path.include?("actionpack") &&
          !path.include?("bundler") &&
          !path.include?("ruby") &&
          !path.include?("gems")
      end

      return "unknown" unless frame

      # Return format: "app/models/user.rb:42:in `method_name'"
      path = frame.path
      # Extract only the relative path (everything after the project root)
      relative_path = if path.include?("/app/")
                        path.split("/app/").last.prepend("app/")
                      elsif path.include?("/spec/")
                        path.split("/spec/").last.prepend("spec/")
                      elsif path.include?("/lib/")
                        path.split("/lib/").last.prepend("lib/")
                      else
                        path
                      end

      "#{relative_path}:#{frame.lineno}:in `#{frame.label}'"
    end
  end
end
