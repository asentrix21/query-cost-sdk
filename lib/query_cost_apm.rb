# frozen_string_literal: true

require_relative "query_cost_apm/version"
require_relative "query_cost_apm/sanitizer"
require_relative "query_cost_apm/fingerprinter"
require_relative "query_cost_apm/aggregator"
require_relative "query_cost_apm/exporter"
require_relative "query_cost_apm/manager"

module QueryCostApm
  class Error < StandardError; end

  # Configuration holder
  class Config
    attr_accessor :api_key, :backend_url, :environment, :export_interval_seconds, :enabled

    def initialize
      @api_key = nil
      @backend_url = nil
      @environment = nil
      @export_interval_seconds = Manager::DEFAULT_EXPORT_INTERVAL_SECONDS
      @enabled = ENV["QUERY_COST_APM_ENABLED"] != "false"  # Default true, disable via env var
    end
  end

  @@config = Config.new
  @@manager = nil
  @@config_lock = Mutex.new

  # Configure the SDK
  #
  # @example
  #   QueryCostApm.configure do |config|
  #     config.api_key = ENV["QUERY_COST_APM_KEY"]
  #     config.backend_url = "https://api.example.com/rollups"
  #     config.environment = ENV["RAILS_ENV"]
  #     config.export_interval_seconds = 60
  #     config.enabled = true
  #   end
  def self.configure
    yield @@config if block_given?

    # Respect environment variable override
    @@config.enabled = ENV["QUERY_COST_APM_ENABLED"] != "false" if ENV.key?("QUERY_COST_APM_ENABLED")

    # Start manager if enabled and configured
    if @@config.enabled && @@config.api_key && @@config.backend_url && @@config.environment
      manager.start
    elsif !@@config.enabled
      manager.stop if @@manager
    end
  end

  # Get current configuration
  def self.config
    @@config
  end

  # Check if SDK is enabled
  def self.enabled
    @@config.enabled
  end

  # Set enabled state (kill switch)
  def self.enabled=(value)
    @@config.enabled = value

    if value && @@config.api_key && @@config.backend_url && @@config.environment
      manager.start
    elsif !value
      manager.stop if @@manager
    end
  end

  # Check if Interceptor is subscribed (via Manager)
  def self.subscribed?
    @@manager&.instance_variable_get(:@interceptor_handle) ? true : false
  end

  # Get or create the Manager singleton
  def self.manager
    @@config_lock.synchronize do
      if @@manager.nil?
        raise "QueryCostApm not configured. Call QueryCostApm.configure first." if @@config.api_key.nil?

        @@manager = Manager.instance(
          api_key: @@config.api_key,
          backend_url: @@config.backend_url,
          environment: @@config.environment,
          export_interval_seconds: @@config.export_interval_seconds
        )
      end
      @@manager
    end
  end

  # Reset configuration (for testing)
  def self.reset_config!
    @@config_lock.synchronize do
      Manager.reset_instance
      @@manager = nil
      @@config = Config.new
    end
  end
end


# Require Interceptor only if Rails is available
begin
  require_relative "query_cost_apm/interceptor"
rescue LoadError
  # ActiveSupport not available; Interceptor will not be loaded
end
