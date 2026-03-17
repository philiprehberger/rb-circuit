# frozen_string_literal: true

module Philiprehberger
  module Circuit
    # Callback registration and firing for state transitions
    module Callbacks
      def on_open(&) = register_callback(:open, &)
      def on_close(&) = register_callback(:close, &)
      def on_half_open(&) = register_callback(:half_open, &)

      # Register a callback for any state transition
      # @yield [from_state, to_state] called on every transition
      def on_reset(&block)
        @mutex.synchronize { @reset_callbacks << block }
        self
      end

      private

      def init_callbacks
        @callbacks = { open: [], close: [], half_open: [] }
        @reset_callbacks = []
      end

      def fire_callbacks(from_state, new_state)
        key = STATE_CALLBACK_MAP[new_state]
        @callbacks[key]&.each(&:call)
        fire_reset_callbacks(from_state, new_state)
      end

      def fire_reset_callbacks(from, to)
        @reset_callbacks.each { |cb| cb.call(from, to) }
      end

      def register_callback(event, &block)
        @mutex.synchronize { @callbacks[event] << block }
        self
      end
    end
  end
end
