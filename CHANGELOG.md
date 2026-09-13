# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-13

### Added

- **Phase 1: Sanitizer** - Defense-in-depth SQL sanitization removes all PII/PHI from queries before export
  - 6-step processing pipeline: binds-check, string-literals, multi-statement-check, bare-literals, IN-collapse, whitespace-normalization
  - Handles edge cases: escaped quotes, JSON operators, Postgres cast syntax
  - 23 comprehensive test cases

- **Phase 2: Fingerprinter** - Deterministic query fingerprinting for aggregation
  - SHA256-based hashing of normalized SQL
  - Enables grouping identical query shapes across invocations
  - 14 test cases

- **Phase 3: Interceptor** - Real-time query capture and call-site attribution
  - Hooks into `ActiveSupport::Notifications` without blocking request path
  - Extracts caller location (application code frame)
  - Filters non-application queries (SCHEMA, transactions, migrations)
  - Fail-open exception handling
  - 14 test cases

- **Phase 4: Aggregator** - In-memory query aggregation and metrics computation
  - Groups queries by fingerprint
  - Computes: count, total/min/max/avg duration, distinct call sites, timestamps
  - Thread-safe with Mutex protection
  - Generates rollup export format
  - 17 test cases

- **Phase 5: Exporter** - HTTP client for backend shipment
  - Real gzip compression (not zlib) matching Content-Encoding header
  - Single send attempt (no retries - fail immediately to avoid queueing backpressure)
  - 2-second timeout per send
  - Fail-open error handling
  - 11 test cases

- **Phase 6: Public API & Configuration** - Single entry point for application integration
  - `QueryCostApm.configure { |c| c.api_key = "..."; c.backend_url = "..."; c.environment = "..." }`
  - Kill switch: `QueryCostApm.enabled = false` (no deploy required)
  - Respects `QUERY_COST_APM_ENABLED` environment variable
  - Manager singleton for periodic export coordination
  - 10 test cases

- **Phase 7: Packaging** - Production-ready gem with security documentation
  - Full gemspec metadata and MIT license
  - README with prominent data-boundary statement (§5.4)
  - Pinned to 0.1.0 (git-installed only, not on RubyGems)
  - 87 total tests, all passing

### Security

- Multi-layer sanitization prevents PII/PHI leakage
- Sanitized queries only (not raw SQL)
- Calls to Interceptor from Manager use callback seam for fail-open guarantee
- Single subscription point prevents duplicate processing
- Exception handling ensures queries never block application

### Known Limitations

- Backend service does not yet exist (this is the client SDK only)
- Gem is git-installed only (not published to RubyGems) pending backend deployment

### Testing

- 87 tests across all 6 phases
- Unit tests for each component
- Integration tests for end-to-end flow
- Critical tests for subscription management and fail-open guarantee
- All tests passing with no external dependencies beyond activesupport
