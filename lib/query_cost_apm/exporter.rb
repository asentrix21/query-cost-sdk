# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "zlib"
require "stringio"

module QueryCostApm
  # Exporter — ships aggregated query metrics to the Query-Cost APM backend.
  #
  # Purpose: Batch aggregate query rollups, serialize to JSON, compress with gzip,
  # and send via HTTPS to the backend for dashboarding and analysis.
  #
  # Design:
  # - Collects rollups in a queue
  # - Batches multiple rollups into a single HTTP request
  # - Gzip compresses the JSON payload (real gzip format, not zlib)
  # - Single attempt per send (no retries — fail immediately to avoid queueing backpressure)
  # - Never raises exceptions (fail-open design) — logs errors instead
  # - Timeout (2s) prevents blocking the application
  class Exporter
    # Default configuration
    DEFAULT_TIMEOUT_SECONDS = 2  # 2000ms max per send attempt (design doc §4.4)
    DEFAULT_BATCH_SIZE = 100  # Max rollups per request

    def initialize(api_key:, backend_url:, environment:, 
                   timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
                   batch_size: DEFAULT_BATCH_SIZE)
      @api_key = api_key
      @backend_url = backend_url
      @environment = environment
      @timeout_seconds = timeout_seconds
      @batch_size = batch_size
      @lock = Mutex.new
      @rollups = []
    end

    # Configuration accessors
    attr_reader :api_key, :backend_url, :environment
    attr_reader :timeout_seconds, :batch_size

    # Add a rollup to the export queue.
    #
    # @param rollup [Hash] — aggregated metrics from Aggregator.rollup
    # @return [void]
    def add_rollup(rollup)
      return if rollup.nil?

      @lock.synchronize do
        @rollups << rollup
      end
    end

    # Get a copy of the current rollup queue.
    #
    # @return [Array<Hash>]
    def rollups
      @lock.synchronize do
        @rollups.dup
      end
    end

    # Clear the rollup queue (typically after successful export).
    #
    # @return [void]
    def clear_rollups
      @lock.synchronize do
        @rollups.clear
      end
    end

    # Build the HTTP payload from queued rollups.
    # Does NOT clear the queue (call clear_rollups explicitly after successful send).
    #
    # @return [Hash] — payload to be JSON serialized and sent
    def build_payload
      @lock.synchronize do
        {
          api_key: @api_key,
          environment: @environment,
          timestamp: Time.now,
          rollups: @rollups.map(&:dup)  # Send copies, don't modify originals
        }
      end
    end

    # Send all queued rollups to the backend.
    # Single attempt (no retries) to avoid queueing backpressure.
    # Timeout is 2s per send attempt. Never raises — catches all errors.
    #
    # @return [true, false] — whether send succeeded
    def send_rollups
      return false if rollups.empty?

      payload = build_payload

      begin
        result = send_once(payload)
        if result
          # On success, clear the queue
          clear_rollups
          return true
        end
      rescue => e
        warn("[QueryCostApm::Exporter] Error sending rollups: #{e.message}") if ENV["QUERY_COST_APM_DEBUG"]
      end

      # Send failed or returned non-2xx
      false
    end

    private

    # Perform a single HTTP send attempt (no retries).
    #
    # @param payload [Hash]
    # @return [true, false]
    def send_once(payload)
      json_payload = JSON.generate(payload)
      gzipped_payload = gzip_compress(json_payload)

      uri = URI.parse(@backend_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == "https"
      http.read_timeout = @timeout_seconds
      http.open_timeout = @timeout_seconds

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Content-Encoding"] = "gzip"
      request["User-Agent"] = "QueryCostApm/1.0"
      request["X-APM-Api-Key"] = @api_key
      request.body = gzipped_payload

      response = http.request(request)

      # 200-299 status codes are considered success
      success = response.code.to_i >= 200 && response.code.to_i < 300
      if ENV["QUERY_COST_APM_DEBUG"]
        puts "[DEBUG] HTTP response code: #{response.code}"
        puts "[DEBUG] HTTP response body: #{response.body.inspect[0..200]}"
      end
      success
    rescue Net::Timeout, Net::OpenTimeout => e
      warn("[QueryCostApm::Exporter] Timeout sending rollups: #{e.message}") if ENV["QUERY_COST_APM_DEBUG"]
      if ENV["QUERY_COST_APM_DEBUG"]
        puts "[DEBUG] HTTP timeout error: #{e.class} - #{e.message}"
      end
      false
    rescue => e
      warn("[QueryCostApm::Exporter] HTTP error: #{e.message}") if ENV["QUERY_COST_APM_DEBUG"]
      if ENV["QUERY_COST_APM_DEBUG"]
        puts "[DEBUG] HTTP error: #{e.class} - #{e.message}"
        puts e.backtrace.take(5).join("\n")
      end
      false
    end

    # Compress JSON payload with real gzip format (not zlib).
    # Returns bytes that match Content-Encoding: gzip header.
    #
    # @param json_str [String]
    # @return [String] gzip-compressed bytes
    def gzip_compress(json_str)
      buffer = StringIO.new
      Zlib::GzipWriter.wrap(buffer) do |gz|
        gz.write(json_str)
      end
      buffer.string
    end
  end
end
