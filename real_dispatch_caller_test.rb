#!/usr/bin/env ruby
# frozen_string_literal: true
#
# REAL-DISPATCH caller-location test. DO NOT MODIFY THIS FILE.
# Run exactly as-is: ruby real_dispatch_caller_test.rb
#
# Design constraints, deliberately:
# - No monkey-patching of any QueryCostApm method.
# - No direct call to Interceptor.process_query anywhere in this file.
# - No second/external subscriber to "sql.active_record" — that was tried and it introduced
#   its own non-excluded stack frame (its own block lives outside query_cost_apm's path),
#   which the filter couldn't tell apart from real application code.
# - Results are observed via Interceptor.subscribe's own on_result callback, so the ONLY
#   call to process_query happens exactly where production calls it: inside interceptor.rb,
#   correctly excluded by the existing path filter.

require "active_support/notifications"
require_relative "lib/query_cost_apm"

captured = []

interceptor_handle = QueryCostApm::Interceptor.subscribe do |result|
  captured << result
end

class User
  def self.find_by_email(_email)
    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      sql: "SELECT * FROM users WHERE email = 'x'",
      binds: [],
      name: "User Load"
    ) { }
  end

  def self.all_active
    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      sql: "SELECT * FROM users WHERE active = true",
      binds: [],
      name: "User Load"
    ) { }
  end
end

class TestController
  def show
    ActiveSupport::Notifications.instrument(
      "sql.active_record",
      sql: "SELECT * FROM users WHERE id = 1",
      binds: [],
      name: "User Load"
    ) { }
  end
end

User.find_by_email("john@example.com")
User.all_active
TestController.new.show

QueryCostApm::Interceptor.unsubscribe(interceptor_handle)

puts "=" * 70
puts "Captured #{captured.size} queries (expected 3)"
puts "=" * 70
captured.each_with_index do |r, i|
  puts "[#{i + 1}] caller_location: #{r[:caller_location].inspect}"
end
puts

errors = []
errors << "Expected 3 captured queries, got #{captured.size}" unless captured.size == 3

expected_methods = %w[find_by_email all_active show]
captured.each_with_index do |r, i|
  loc = r[:caller_location].to_s
  expected = expected_methods[i]
  errors << "Result #{i + 1}: caller_location is 'unknown'" if loc == "unknown"
  errors << "Result #{i + 1}: expected caller_location to reference '#{expected}', got #{loc.inspect}" unless loc.include?(expected)
end

locations = captured.map { |r| r[:caller_location] }
errors << "Not all caller_locations are distinct: #{locations.inspect}" if locations.uniq.size != locations.size

if errors.empty?
  puts "ALL ASSERTIONS PASSED"
else
  puts "FAILURES:"
  errors.each { |e| puts "  - #{e}" }
  exit 1
end
