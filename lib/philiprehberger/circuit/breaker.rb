# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Circuit breaker with three states: closed, open, half-open
    class Breaker
      attr_reader :name

      # @param name [Symbol, String] breaker name
      # @param threshold [Integer] failures before opening
      # @param timeout [Numeric] seconds before trying half-open
      # @param error_classes [Array<Class>] exception classes to count
      def initialize(name, threshold: 5, timeout: 30, error_classes: [StandardError])
        @name = name
        @threshold = threshold
        @timeout = timeout
        @error_classes = error_classes
        @mutex = Mutex.new
        @callbacks = { open: [], close: [], half_open: [] }
        @state = CLOSED
        @failure_count = 0
        @last_failure_time = nil
      end

      # Execute a block with circuit protection
      #
      # @param fallback [Proc, nil] fallback when circuit is open
      # @return [Object] block result or fallback result
      # @raise [OpenError] if open and no fallback
      def call(fallback: nil, &block)
        @mutex.synchronize { handle_state(fallback, &block) }
      end

      # Current circuit state
      # @return [Symbol] :closed, :open, or :half_open
      def state
        @mutex.synchronize { @state }
      end

      # Force circuit back to closed state
      def reset!
        @mutex.synchronize { transition_to(CLOSED) }
      end

      def on_open(&) = register_callback(:open, &)
      def on_close(&) = register_callback(:close, &)
      def on_half_open(&) = register_callback(:half_open, &)

      private

      def handle_state(fallback, &)
        case @state
        when CLOSED then execute_closed(&)
        when OPEN then handle_open(fallback, &)
        when HALF_OPEN then execute_half_open(&)
        end
      end

      def execute_closed(&block)
        result = block.call
        @failure_count = 0
        result
      rescue *@error_classes => e
        record_failure
        raise e
      end

      def handle_open(fallback, &)
        if timeout_elapsed?
          transition_to(HALF_OPEN)
          return execute_half_open(&)
        end
        return fallback.call if fallback

        raise OpenError, "Circuit #{@name} is open"
      end

      def execute_half_open(&block)
        result = block.call
        transition_to(CLOSED)
        result
      rescue *@error_classes => e
        transition_to(OPEN)
        raise e
      end

      def record_failure
        @failure_count += 1
        @last_failure_time = Time.now
        transition_to(OPEN) if @failure_count >= @threshold
      end

      def timeout_elapsed?
        @last_failure_time && (Time.now - @last_failure_time) >= @timeout
      end

      def transition_to(new_state)
        @state = new_state
        @failure_count = 0 if new_state == CLOSED
        @last_failure_time = Time.now if new_state == OPEN
        fire_callbacks(new_state)
      end

      def fire_callbacks(state_name)
        key = { CLOSED => :close, OPEN => :open, HALF_OPEN => :half_open }[state_name]
        @callbacks[key]&.each(&:call)
      end

      def register_callback(event, &block)
        @mutex.synchronize { @callbacks[event] << block }
        self
      end
    end
  end
end
