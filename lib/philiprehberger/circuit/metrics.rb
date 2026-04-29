# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Thread-safe counters and state change log for monitoring
    module Metrics
      def metrics
        @mutex.synchronize { metrics_snapshot }
      end

      # Most recent failure recorded by the breaker, or nil when none has
      # occurred since the last reset.
      #
      # @return [Hash, nil] { at: Time, error_class: Class, message: String } or nil
      def last_failure
        @mutex.synchronize { @last_failure&.dup }
      end

      # Zero counters and clear the state-change log without altering
      # the circuit's current state or transition timestamps. Also clears
      # the last_failure record.
      def metrics_reset!
        @mutex.synchronize do
          @success_count = 0
          @metrics_failure_count = 0
          @rejected_count = 0
          @state_changes = []
          @last_failure = nil
        end
        self
      end

      private

      def init_metrics
        @success_count = 0
        @metrics_failure_count = 0
        @rejected_count = 0
        @state_changes = []
        @last_failure = nil
      end

      def record_success
        @success_count += 1
      end

      def record_rejection
        @rejected_count += 1
      end

      def record_metrics_failure
        @metrics_failure_count += 1
      end

      def capture_failure(error)
        @last_failure = { at: Time.now, error_class: error.class, message: error.message }
      end

      def record_state_change(from, to)
        @state_changes << { from: from, to: to, at: Time.now }
      end

      def metrics_snapshot
        {
          success_count: @success_count,
          failure_count: @metrics_failure_count,
          rejected_count: @rejected_count,
          state_changes: @state_changes.dup
        }
      end
    end
  end
end
