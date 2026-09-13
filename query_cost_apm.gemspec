# frozen_string_literal: true

require_relative "lib/query_cost_apm/version"

Gem::Specification.new do |spec|
  spec.name = "query_cost_apm"
  spec.version = QueryCostApm::VERSION
  spec.authors = ["asentrix21"]
  spec.email = ["sushantbehal.awge@gmail.com"]

  spec.summary = "Cost-first query observability for Rails applications"
  spec.description = "Cost-first database query observability SDK for Rails. Instruments queries, sanitizes for PII/PHI, fingerprints by shape, and aggregates metrics with call-site attribution. Ships periodic rollups to the Query-Cost APM backend for dashboarding. Defense-in-depth sanitization ensures sensitive values never leave your process."
  spec.homepage = "https://github.com/asentrix21/query-cost-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  # Note: This gem is currently git-installed only (not published to RubyGems)
  # pending backend service deployment. Install from GitHub:
  # gem 'query_cost_apm', git: 'https://github.com/asentrix21/query-cost-sdk.git'

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["security_policy_uri"] = "#{spec.homepage}/blob/main/SECURITY.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Development dependencies: activesupport is flexible to work with multiple Rails versions
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "activesupport", ">= 5.2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
