# frozen_string_literal: true

require "spec_helper"

RSpec.describe QueryCostApm::Aggregator do
  let(:aggregator) { QueryCostApm::Aggregator.new }

  describe "#add_query_result" do
    it "accepts a query result hash and stores it" do
      result = {
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.5,
        caller_location: "app/models/user.rb:42:in `find'"
      }

      expect { aggregator.add_query_result(result) }.not_to raise_error
    end

    it "handles nil input gracefully" do
      expect { aggregator.add_query_result(nil) }.not_to raise_error
    end

    it "handles empty hash gracefully" do
      expect { aggregator.add_query_result({}) }.not_to raise_error
    end
  end

  describe "#aggregates" do
    it "returns an empty hash initially" do
      expect(aggregator.aggregates).to eq({})
    end

    it "aggregates multiple queries by fingerprint" do
      result1 = {
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      }

      result2 = {
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      }

      result3 = {
        fingerprint_hash: "xyz789",
        normalized_sql: "SELECT * FROM posts WHERE user_id = ?",
        duration_ms: 5.5,
        caller_location: "app/models/post.rb:10:in `for_user'"
      }

      aggregator.add_query_result(result1)
      aggregator.add_query_result(result2)
      aggregator.add_query_result(result3)

      aggs = aggregator.aggregates

      # Should have 2 fingerprints
      expect(aggs.keys.length).to eq(2)
      expect(aggs).to have_key("abc123")
      expect(aggs).to have_key("xyz789")
    end
  end

  describe "#aggregates[:fingerprint_hash]" do
    it "includes count of queries" do
      3.times do |i|
        aggregator.add_query_result({
          fingerprint_hash: "abc123",
          normalized_sql: "SELECT * FROM users WHERE id = ?",
          duration_ms: 10.0 + i,
          caller_location: "app/models/user.rb:42:in `find'"
        })
      end

      agg = aggregator.aggregates["abc123"]
      expect(agg[:count]).to eq(3)
    end

    it "includes total duration" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      agg = aggregator.aggregates["abc123"]
      expect(agg[:total_duration_ms]).to eq(30.0)
    end

    it "includes min duration" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 50.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 30.0,
        caller_location: "app/models/user.rb:60:in `search'"
      })

      agg = aggregator.aggregates["abc123"]
      expect(agg[:min_duration_ms]).to eq(10.0)
    end

    it "includes max duration" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 50.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 30.0,
        caller_location: "app/models/user.rb:60:in `search'"
      })

      agg = aggregator.aggregates["abc123"]
      expect(agg[:max_duration_ms]).to eq(50.0)
    end

    it "includes the normalized SQL" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      agg = aggregator.aggregates["abc123"]
      expect(agg[:normalized_sql]).to eq("SELECT * FROM users WHERE id = ?")
    end

    it "includes an array of distinct caller locations" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 15.0,
        caller_location: "app/models/user.rb:42:in `find'"  # Duplicate
      })

      agg = aggregator.aggregates["abc123"]
      expect(agg[:caller_locations]).to be_an(Array)
      expect(agg[:caller_locations].length).to eq(2)
      expect(agg[:caller_locations]).to include("app/models/user.rb:42:in `find'")
      expect(agg[:caller_locations]).to include("app/models/user.rb:50:in `find_all'")
    end

    it "includes timestamp of first and last query" do
      time_before = Time.now
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })
      time_middle = Time.now

      sleep 0.01  # Small delay to make times differ

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })
      time_after = Time.now

      agg = aggregator.aggregates["abc123"]
      expect(agg[:first_seen]).to be_a(Time)
      expect(agg[:last_seen]).to be_a(Time)
      expect(agg[:first_seen]).to be <= time_middle
      expect(agg[:last_seen]).to be >= time_middle
    end
  end

  describe "#clear" do
    it "clears all aggregates" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      expect(aggregator.aggregates).not_to be_empty

      aggregator.clear

      expect(aggregator.aggregates).to be_empty
    end
  end

  describe "#rollup" do
    it "returns a hash with all aggregated data" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "xyz789",
        normalized_sql: "SELECT * FROM posts WHERE user_id = ?",
        duration_ms: 5.5,
        caller_location: "app/models/post.rb:10:in `for_user'"
      })

      rollup = aggregator.rollup

      expect(rollup).to be_a(Hash)
      expect(rollup).to have_key(:fingerprints)
      expect(rollup[:fingerprints]).to be_an(Array)
      expect(rollup[:fingerprints].length).to eq(2)
    end

    it "includes fingerprint entries with all metrics" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      rollup = aggregator.rollup
      fingerprints = rollup[:fingerprints]

      fp = fingerprints.first
      expect(fp).to have_key(:fingerprint_hash)
      expect(fp).to have_key(:normalized_sql)
      expect(fp).to have_key(:count)
      expect(fp).to have_key(:total_duration_ms)
      expect(fp).to have_key(:min_duration_ms)
      expect(fp).to have_key(:max_duration_ms)
      expect(fp).to have_key(:caller_locations)
      expect(fp).to have_key(:first_seen)
      expect(fp).to have_key(:last_seen)
    end

    it "includes a summary with total metrics" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "xyz789",
        normalized_sql: "SELECT * FROM posts WHERE user_id = ?",
        duration_ms: 5.0,
        caller_location: "app/models/post.rb:10:in `for_user'"
      })

      rollup = aggregator.rollup

      expect(rollup).to have_key(:summary)
      summary = rollup[:summary]
      expect(summary[:total_fingerprints]).to eq(2)
      expect(summary[:total_queries]).to eq(3)
      expect(summary[:total_duration_ms]).to eq(35.0)
    end

    it "includes a timestamp in the rollup" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      time_before = Time.now
      rollup = aggregator.rollup
      time_after = Time.now

      expect(rollup).to have_key(:timestamp)
      expect(rollup[:timestamp]).to be_a(Time)
      expect(rollup[:timestamp]).to be >= time_before
      expect(rollup[:timestamp]).to be <= time_after
    end
  end

  describe "thread safety" do
    it "handles concurrent additions without data corruption" do
      aggregator = QueryCostApm::Aggregator.new
      threads = []
      results_per_thread = 100

      10.times do |thread_idx|
        threads << Thread.new do
          results_per_thread.times do |i|
            aggregator.add_query_result({
              fingerprint_hash: "fps_#{thread_idx % 3}",  # 3 different fingerprints
              normalized_sql: "SELECT * FROM table_#{thread_idx % 3}",
              duration_ms: 10.0 + i,
              caller_location: "file_#{thread_idx}.rb:#{i}:in `method'"
            })
          end
        end
      end

      threads.each(&:join)

      aggs = aggregator.aggregates
      # Each fingerprint should have results from multiple threads
      expect(aggs.keys.length).to eq(3)

      # Total count should be 10 threads * 100 results per thread = 1000
      total_count = aggs.values.sum { |agg| agg[:count] }
      expect(total_count).to eq(1000)
    end
  end

  describe "average duration calculation" do
    it "calculates average duration correctly" do
      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 10.0,
        caller_location: "app/models/user.rb:42:in `find'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 20.0,
        caller_location: "app/models/user.rb:50:in `find_all'"
      })

      aggregator.add_query_result({
        fingerprint_hash: "abc123",
        normalized_sql: "SELECT * FROM users WHERE id = ?",
        duration_ms: 30.0,
        caller_location: "app/models/user.rb:60:in `search'"
      })

      agg = aggregator.aggregates["abc123"]
      expected_avg = 20.0  # (10 + 20 + 30) / 3
      expect(agg[:avg_duration_ms]).to be_within(0.01).of(expected_avg)
    end
  end
end
