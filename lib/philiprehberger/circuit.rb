# frozen_string_literal: true

require_relative 'circuit/version'
require_relative 'circuit/state'
require_relative 'circuit/metrics'
require_relative 'circuit/callbacks'
require_relative 'circuit/backoff'
require_relative 'circuit/execution'
require_relative 'circuit/breaker'

module Philiprehberger
  module Circuit
    class Error < StandardError; end

    # Raised when calling through an open circuit with no fallback
    class OpenError < Error; end
  end
end
