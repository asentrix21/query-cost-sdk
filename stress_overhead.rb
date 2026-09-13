require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require_relative "lib/query_cost_apm"

N = 5000
sql = "SELECT * FROM users WHERE email = 'test@example.com' AND active = true"

start = Time.now
N.times { ActiveSupport::Notifications.instrument("sql.active_record", sql: sql, binds: [], name: "User Load") { } }
baseline = Time.now - start

handle = QueryCostApm::Interceptor.subscribe { |result| }
start = Time.now
N.times { ActiveSupport::Notifications.instrument("sql.active_record", sql: sql, binds: [], name: "User Load") { } }
with_sdk = Time.now - start
QueryCostApm::Interceptor.unsubscribe(handle)

puts "Baseline (no SDK):  #{(baseline * 1000).round(2)}ms total, #{(baseline * 1000 / N).round(4)}ms/query"
puts "With SDK active:    #{(with_sdk * 1000).round(2)}ms total, #{(with_sdk * 1000 / N).round(4)}ms/query"
puts "Overhead per query:  #{((with_sdk - baseline) * 1000 / N).round(4)}ms"