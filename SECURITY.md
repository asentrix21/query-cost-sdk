# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in query-cost-apm, please email **security@querycost.local** with the following information:

- Description of the vulnerability
- Steps to reproduce
- Impact assessment
- Suggested fix (if applicable)

**Do not open a public GitHub issue** for security vulnerabilities. This allows us to address the issue before public disclosure.

## Security Design

### Defense-in-Depth Sanitization

This gem is designed with security as a core principle. Database queries often contain sensitive information (user IDs, email addresses, payment data, etc.). The sanitizer uses a multi-layer approach to ensure this data never leaves your process:

**6-Step Processing Pipeline:**
1. **Binds-check** - Validates and extracts bind parameters
2. **String-literals** - Replaces string values with placeholders
3. **Multi-statement-check** - Prevents SQL injection attacks
4. **Bare-literals** - Replaces numeric literals with placeholders
5. **IN-collapse** - Normalizes IN lists to single placeholder
6. **Whitespace-normalization** - Standardizes spacing and case

### What Leaves Your Process

Only the following **sanitized** data is sent to the backend:
- Query fingerprints (hashes of normalized SQL with all values replaced by placeholders)
- Aggregate metrics (count, durations, not raw query data)
- Call-site metadata (file path and line number, not user data)
- API key and environment name

### What Never Leaves Your Process

- Raw parameter values (IDs, emails, amounts, etc.)
- Row data or result sets
- Raw SQL text
- Passwords, secrets, PII, or PHI

## Code Review

The sanitizer is intentionally **small and auditable**. If you have security concerns about what data leaves your process:

1. Read `lib/query_cost_apm/sanitizer.rb` (79 lines)
2. Read the test cases in `spec/sanitizer_spec.rb` (202 lines covering real-world patterns)
3. Review the test file to see exactly what the sanitizer does on adversarial inputs

## Fail-Open Design

All exception handling is designed to fail open:

- If sanitization fails, the query is skipped (not sent)
- If fingerprinting fails, the query is skipped
- If export fails, the gem logs at debug level only (never blocks your app)
- If the subscription callback raises an exception, it's caught and logged (never propagates to application code)

## Compliance

This SDK is designed to help companies achieve query cost observability while maintaining **strict data privacy**. It's suitable for environments where:

- You need query cost insights
- You're subject to data protection regulations (GDPR, HIPAA, CCPA, etc.)
- You cannot send raw SQL or parameter values to external services

## Third-Party Dependencies

### Runtime
- `activesupport` (>= 5.2) - Rails dependency, used for `ActiveSupport::Notifications`

### Development Only
- `rspec` (~> 3.0) - Testing

No other external dependencies. All core functionality (sanitization, fingerprinting, HTTP export) is implemented directly.

## Version Support

- **Ruby:** 2.6.0+
- **Rails:** 5.2+

Security updates will be backported to supported versions.
