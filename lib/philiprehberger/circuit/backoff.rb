# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Exponential backoff for open-to-half-open timeout
    module Backoff
      private

      def init_backoff(strategy, base_timeout, max_timeout)
        @timeout_strategy = strategy
        @base_timeout = base_timeout
        @max_timeout = max_timeout
        @consecutive_opens = 0
      end

      def current_timeout
        return @base_timeout unless @timeout_strategy == :exponential

        computed = @base_timeout * (2**@consecutive_opens)
        [computed, @max_timeout].min
      end

      def increment_open_count
        @consecutive_opens += 1
      end

      def reset_open_count
        @consecutive_opens = 0
      end
    end
  end
end
