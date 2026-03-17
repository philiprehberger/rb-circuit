# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Thread-safe counters and state change log for monitoring
    module Metrics
      def metrics
        @mutex.synchronize { metrics_snapshot }
      end

      private

      def init_metrics
        @success_count = 0
        @metrics_failure_count = 0
        @rejected_count = 0
        @state_changes = []
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
