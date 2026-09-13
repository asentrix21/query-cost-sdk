# frozen_string_literal: true

require "spec_helper"
require "active_support/notifications"

RSpec.describe QueryCostApm::Manager do
  after do
    QueryCostApm.reset_config!
  end

  it "fail-open: an exception in the aggregator never propagates out of instrument" do
    manager = described_class.new(api_key: "test-key", backend_url: "http://localhost:3000/ingest", environment: "test")
    call_count = 0
    manager.aggregator.define_singleton_method(:add_query_result) do |result|
      call_count += 1
      raise StandardError, "Intentional test error"
    end

    expect {
      ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT * FROM users", name: "User Load", binds: []) { }
    }.not_to raise_error

    expect(call_count).to be > 0
    manager.stop
  end

  it "processes each query exactly once (no duplicate subscriptions)" do
    manager = described_class.new(api_key: "test-key", backend_url: "http://localhost:3000/ingest", environment: "test")

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT * FROM users WHERE id = 999", name: "User Load", binds: []) { }

    agg = manager.aggregator.aggregates.values.first
    expect(agg[:count]).to eq(1)
    manager.stop
  end

  it "stops receiving queries after #stop is called" do
    manager = described_class.new(api_key: "test-key", backend_url: "http://localhost:3000/ingest", environment: "test")

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT * FROM users WHERE id = 1", name: "User Load", binds: []) { }
    count_before = manager.aggregator.aggregates.length

    manager.stop

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT * FROM posts WHERE user_id = 1", name: "Post Load", binds: []) { }
    count_after = manager.aggregator.aggregates.length

    expect(count_after).to eq(count_before)
  end
end