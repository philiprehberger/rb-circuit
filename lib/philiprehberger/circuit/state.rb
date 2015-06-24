# frozen_string_literal: true

module Philiprehberger
  module Circuit
    CLOSED    = :closed
    OPEN      = :open
    HALF_OPEN = :half_open

    STATE_CALLBACK_MAP = { CLOSED => :close, OPEN => :open, HALF_OPEN => :half_open }.freeze
  end
end
