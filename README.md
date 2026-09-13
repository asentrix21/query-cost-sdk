# QueryCostApm

**Cost-first query observability for Rails applications.**

Instruments your Rails application to capture and aggregate database query execution metrics, fingerprinted by query shape and call site. Ships periodic rollups to the Query-Cost APM SaaS backend, which ranks queries by cost contribution and surfaces them on a developer-friendly dashboard.

## ⚠️ Data Boundary (Read This First)

This gem instruments your database traffic. Here's exactly what leaves your process and what never does:

**What leaves your process (sent to Query-Cost APM backend):**
- **Sanitized query fingerprints** — the query shape with all literal values replaced by placeholders (e.g., `SELECT * FROM users WHERE id = ?`)
- **Aggregate metrics** — call count, total duration, min/max query times, per fingerprint
- **Call site metadata** — the Rails application code location (controller/model/view) that triggered the query, used for attribution but never for grouping queries (multiple call sites map to the same query fingerprint)
- **Your API key** and environment name (production, staging, etc.)

**What never leaves your process:**
- Raw parameter values (user IDs, emails, payment amounts, etc.)
- Row data or result sets
- Raw SQL text (only sanitized fingerprints)
- Passwords, secrets, PII, or PHI — the sanitizer is designed to exclude these

**How it works:**
- The gem uses Rails' `ActiveSupport::Notifications` hook to observe queries *after* they complete, never blocking your application's request path.
- Query sanitization happens entirely within your process; sensitive values are never even serialized into the exporter's buffer.
- All exports are gzipped HTTPS with a timeout; export failures don't block your app.

If you need to know exactly what the sanitizer does, read `lib/query_cost_apm/sanitizer.rb` — it's open-source, small, and the most sensitive piece of this gem. If you're uncomfortable with that level of access to your database traffic, don't use this gem.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'query_cost_apm'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install query_cost_apm

## Usage

Create an initializer in your Rails app:

```ruby
# config/initializers/query_cost_apm.rb
QueryCostApm.configure do |config|
  config.api_key = ENV['QUERY_COST_APM_API_KEY']
  config.environment = ENV['RAILS_ENV']
  # Optional: change export interval (default 60s)
  # config.export_interval_seconds = 30
end
```

That's it — the gem hooks into Rails' query notifications automatically once required and configured.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Security & Contributing

- This gem is designed with defense-in-depth sanitization. Please review `lib/query_cost_apm/sanitizer.rb` if you have concerns about what leaves your process.
- Bug reports and security issues: open an issue on GitHub at https://github.com/sushant-behal/query-cost-apm-ruby.
- For security concerns specific to sanitization, please email privately rather than opening a public issue.

## License

MIT License. See `LICENSE` for details.
