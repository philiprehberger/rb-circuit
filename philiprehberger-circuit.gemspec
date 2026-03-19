# frozen_string_literal: true

require_relative 'lib/philiprehberger/circuit/version'

Gem::Specification.new do |spec|
  spec.name          = 'philiprehberger-circuit'
  spec.version       = Philiprehberger::Circuit::VERSION
  spec.authors       = ['Philip Rehberger']
  spec.email         = ['me@philiprehberger.com']

  spec.summary       = 'Minimal circuit breaker with three states and configurable thresholds'
  spec.description   = 'Circuit breaker pattern with closed, open, and half-open states, ' \
                       'configurable failure thresholds, timeout, error class filtering, ' \
                       'event callbacks, metrics, and exponential backoff.'
  spec.homepage      = 'https://github.com/philiprehberger/rb-circuit'
  spec.license       = 'MIT'

  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
