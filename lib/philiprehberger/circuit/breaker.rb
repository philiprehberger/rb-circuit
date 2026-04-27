# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Circuit breaker with three states: closed, open, half-open
    class Breaker
      include Metrics
      include Callbacks
      include Backoff
      include Execution

      attr_reader :name

      # @param name [Symbol, String] breaker name
      # @param threshold [Integer] failures before opening
      # @param timeout [Numeric] seconds before trying half-open
      # @param error_classes [Array<Class>] exception classes to count
      # @param half_open_requests [Integer] max probe requests in half-open
      # @param timeout_strategy [Symbol] :fixed or :exponential
      # @param base_timeout [Numeric] base timeout for exponential backoff
      # @param max_timeout [Numeric] max timeout cap for exponential backoff
      def initialize(name, **opts)
        @name = name
        @mutex = Mutex.new
        init_core_state(opts)
        init_callbacks
        init_metrics
        init_backoff_config(opts)
      end

      # Execute a block with circuit protection
      def call(fallback: nil, &block)
        @mutex.synchronize { handle_state(fallback, &block) }
      end

      # Current circuit state
      def state
        @mutex.synchronize { @state }
      end

      # Force circuit back to closed state
      def reset!
        @mutex.synchronize do
          @forced = false
          transition_to(CLOSED)
        end
      end

      # Force circuit to open state (administrative trip)
      def trip!
        @mutex.synchronize { transition_to(OPEN) }
      end

      # Force circuit to open state for maintenance; rejects all calls until reset
      def force_open!
        @mutex.synchronize do
          transition_to(OPEN)
          @forced = true
        end
      end

      # Force circuit to closed state for maintenance; accepts all calls until reset
      def force_closed!
        @mutex.synchronize do
          transition_to(CLOSED)
          @forced = true
        end
      end

      # Whether the breaker is in a manually forced state
      def forced?
        @mutex.synchronize { @forced }
      end

      private

      def init_core_state(opts)
        @threshold = opts.fetch(:threshold, 5)
        @error_classes = opts.fetch(:error_classes, [StandardError])
        @half_open_max = opts.fetch(:half_open_requests, 1)
        @state = CLOSED
        @failure_count = 0
        @last_failure_time = nil
        @half_open_count = 0
        @forced = false
      end

      def init_backoff_config(opts)
        strategy = opts.fetch(:timeout_strategy, :fixed)
        base = opts.fetch(:base_timeout, opts.fetch(:timeout, 30))
        max = opts.fetch(:max_timeout, base * 32)
        init_backoff(strategy, base, max)
      end

      def record_failure
        @failure_count += 1
        record_metrics_failure
        @last_failure_time = Time.now
        return if @forced

        transition_to(OPEN) if @failure_count >= @threshold
      end

      def timeout_elapsed?
        @last_failure_time && (Time.now - @last_failure_time) >= current_timeout
      end

      def transition_to(new_state)
        old_state = @state
        @state = new_state
        apply_side_effects(old_state, new_state)
        record_state_change(old_state, new_state)
        fire_callbacks(old_state, new_state)
      end

      def apply_side_effects(_old_state, new_state)
        case new_state
        when CLOSED then reset_all_counters
        when OPEN then mark_open
        when HALF_OPEN then @half_open_count = 0
        end
      end

      def reset_all_counters
        @failure_count = 0
        @half_open_count = 0
        reset_open_count
      end

      def mark_open
        @last_failure_time = Time.now
        @half_open_count = 0
        increment_open_count
      end
    end
  end
end
