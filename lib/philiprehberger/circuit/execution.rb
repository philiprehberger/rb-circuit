# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Execution logic for each circuit state
    module Execution
      private

      def handle_state(fallback, &)
        case @state
        when CLOSED then execute_closed(&)
        when OPEN then handle_open(fallback, &)
        when HALF_OPEN then try_half_open(fallback, &)
        end
      end

      def execute_closed(&block)
        result = block.call
        @failure_count = 0
        record_success
        result
      rescue *@error_classes => e
        capture_failure(e)
        record_failure
        raise e
      end

      def handle_open(fallback, &)
        return reject_request(fallback) if @forced
        return open_to_half_open(fallback, &) if timeout_elapsed?

        reject_request(fallback)
      end

      def open_to_half_open(fallback, &)
        transition_to(HALF_OPEN)
        try_half_open(fallback, &)
      end

      def try_half_open(fallback, &)
        return reject_request(fallback) if @half_open_count >= @half_open_max

        execute_half_open(&)
      end

      def reject_request(fallback)
        record_rejection
        return fallback.call if fallback

        raise OpenError, "Circuit #{@name} is open"
      end

      def execute_half_open(&block)
        @half_open_count += 1
        result = block.call
        transition_to(CLOSED)
        record_success
        result
      rescue *@error_classes => e
        capture_failure(e)
        transition_to(OPEN)
        raise e
      end
    end
  end
end
