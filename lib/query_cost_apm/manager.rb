# frozen_string_literal: true

module QueryCostApm
  # Manager — central coordinator for the SDK.
  #
  # Responsibilities:
  # - Holds Aggregator and Exporter instances
  # - Runs periodic export on a background thread
  # - Manages Interceptor subscription lifecycle via callback
  # - Implements singleton pattern for application-level access
  class Manager
    DEFAULT_EXPORT_INTERVAL_SECONDS = 60

    def initialize(api_key:, backend_url:, environment:,
                   export_interval_seconds: DEFAULT_EXPORT_INTERVAL_SECONDS)
      @api_key = api_key
      @backend_url = backend_url
      @environment = environment
      @export_interval_seconds = export_interval_seconds
      @running = false
      @export_thread = nil
      @interceptor_handle = nil
      @lock = Mutex.new

      # Initialize sub-components
      @aggregator = Aggregator.new
      @exporter = Exporter.new(
        api_key: api_key,
        backend_url: backend_url,
        environment: environment
      )

      # Subscribe Interceptor with callback that feeds results into aggregator
      # This is the single subscription point for query capture
      @interceptor_handle = Interceptor.subscribe do |result|
        @aggregator.add_query_result(result) if result
      end
    end

    attr_reader :api_key, :backend_url, :environment
    attr_reader :export_interval_seconds
    attr_reader :aggregator, :exporter

    def running?
      @lock.synchronize { @running }
    end

    # Start the periodic export loop
    def start
      @lock.synchronize do
        return if @running
        @running = true
      end

      @export_thread = Thread.new do
        export_loop
      end
    end

    # Stop the periodic export loop and unsubscribe from notifications
    def stop
      @lock.synchronize do
        @running = false
      end

      @export_thread.join if @export_thread
      @export_thread = nil

      # Clean up Interceptor subscription
      if @interceptor_handle
        Interceptor.unsubscribe(@interceptor_handle)
        @interceptor_handle = nil
      end
    end

    # Export immediately (used for testing and manual flushes)
    def export_now!
      rollup = @aggregator.rollup
      return false if rollup.nil? || rollup[:fingerprints].empty?

      @exporter.add_rollup(rollup)
      result = @exporter.send_rollups
      @aggregator.clear
      result
    end

    # Singleton pattern
    @@instance = nil
    @@instance_lock = Mutex.new

    def self.instance(api_key: nil, backend_url: nil, environment: nil,
                      export_interval_seconds: DEFAULT_EXPORT_INTERVAL_SECONDS)
      if @@instance.nil?
        raise "Must provide api_key, backend_url, and environment on first call" if api_key.nil? || backend_url.nil? || environment.nil?
        @@instance_lock.synchronize do
          @@instance = new(
            api_key: api_key,
            backend_url: backend_url,
            environment: environment,
            export_interval_seconds: export_interval_seconds
          ) if @@instance.nil?
        end
      end
      @@instance
    end

    def self.reset_instance
      @@instance_lock.synchronize do
        @@instance.stop if @@instance  # Always stop, not just if running
        @@instance = nil
      end
    end

    private

    def export_loop
      while @lock.synchronize { @running }
        sleep(@export_interval_seconds)

        begin
          # Generate rollup from aggregator
          rollup = @aggregator.rollup
          next if rollup.nil? || rollup[:fingerprints].empty?

          # Add to exporter queue
          @exporter.add_rollup(rollup)

          # Attempt send
          @exporter.send_rollups

          # Clear aggregator for next period
          @aggregator.clear
        rescue => e
          warn("[QueryCostApm::Manager] Error in export loop: #{e.message}") if ENV["QUERY_COST_APM_DEBUG"]
        end
      end
    end
  end
end
