require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require_relative "lib/query_cost_apm"

handle = QueryCostApm::Interceptor.subscribe { |result| }

600.times do |batch|
  # Vary the query shape so distinct fingerprints actually accumulate
  50.times do |i|
    sql = "SELECT * FROM table_#{batch}_#{i} WHERE id = #{i}"
    ActiveSupport::Notifications.instrument("sql.active_record", sql: sql, binds: [], name: "Load") { }
  end
  rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
  puts "batch #{batch}: #{(rss_kb / 1024.0).round(2)} MB RSS" if batch % 10 == 0
  sleep 0.1
end

QueryCostApm::Interceptor.unsubscribe(handle)