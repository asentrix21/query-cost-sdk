# frozen_string_literal: true

require "spec_helper"
require "zlib"
require "stringio"

RSpec.describe QueryCostApm::Exporter do
  let(:exporter) { described_class.new(api_key: "test-key", backend_url: "http://localhost:3000/ingest", environment: "test") }
  let(:sample_rollup) do
    {
      timestamp: Time.now,
      fingerprints: [{
        fingerprint_hash: "abc123", normalized_sql: "SELECT * FROM users", count: 5,
        total_duration_ms: 100.0, min_duration_ms: 10.0, max_duration_ms: 30.0,
        avg_duration_ms: 20.0, caller_locations: ["file.rb:10"]
      }]
    }
  end

  it "compresses the payload as real gzip, not raw zlib deflate" do
    exporter.add_rollup(sample_rollup)
    json = JSON.generate(exporter.build_payload)
    gzipped = exporter.send(:gzip_compress, json)

    expect(gzipped.bytes[0, 2]).to eq([0x1F, 0x8B])
  end

  it "round-trips cleanly through GzipReader" do
    exporter.add_rollup(sample_rollup)
    payload = exporter.build_payload
    json = JSON.generate(payload)
    gzipped = exporter.send(:gzip_compress, json)

    decompressed = Zlib::GzipReader.new(StringIO.new(gzipped)).read
    expect(JSON.parse(decompressed)["environment"]).to eq(JSON.parse(json)["environment"])
  end

  it "makes exactly one attempt and does not retry on failure" do
    failing_exporter = described_class.new(api_key: "test-key", backend_url: "http://localhost:9999/ingest", environment: "test", timeout_seconds: 1)
    failing_exporter.add_rollup(sample_rollup)

    attempts = 0
    original = failing_exporter.method(:send_once)
    failing_exporter.define_singleton_method(:send_once) do |payload|
      attempts += 1
      original.call(payload)
    end

    start = Time.now
    result = failing_exporter.send_rollups
    elapsed = Time.now - start

    expect(attempts).to eq(1)
    expect(elapsed).to be < 5
    expect(result).to eq(false)
  end

  it "defaults to a 2 second timeout" do
    expect(exporter.timeout_seconds).to eq(2)
  end
end