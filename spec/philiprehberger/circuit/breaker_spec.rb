# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::Circuit::Breaker do
  subject(:breaker) { described_class.new(:test, threshold: 3, timeout: 1) }

  describe '#trip!' do
    it 'transitions from closed to open' do
      expect(breaker.state).to eq(:closed)
      breaker.trip!
      expect(breaker.state).to eq(:open)
    end

    it 'transitions from half_open to open' do
      # Use half_open_requests: 0 so the first post-timeout call transitions to
      # half_open but rejects without running the block, leaving state in half_open.
      b = described_class.new(:test, threshold: 1, timeout: 0.1, half_open_requests: 0)
      b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      sleep 0.15
      b.call(fallback: -> { :nope }) { 42 }
      expect(b.state).to eq(:half_open)
      b.trip!
      expect(b.state).to eq(:open)
    end

    it 'is idempotent when already open' do
      breaker.trip!
      expect(breaker.state).to eq(:open)
      breaker.trip!
      expect(breaker.state).to eq(:open)
    end

    it 'fires on_open callback' do
      called = false
      breaker.on_open { called = true }
      breaker.trip!
      expect(called).to be true
    end

    it 'fires on_open callback even when already open (mirrors reset! pattern)' do
      open_count = 0
      breaker.on_open { open_count += 1 }
      breaker.trip!
      breaker.trip!
      expect(open_count).to eq(2)
    end

    it 'fires on_reset callback with from and to states' do
      transitions = []
      breaker.on_reset { |from, to| transitions << [from, to] }
      breaker.trip!
      expect(transitions.last).to eq(%i[closed open])
    end

    it 'records the state change in metrics' do
      breaker.trip!
      changes = breaker.metrics[:state_changes]
      expect(changes.last[:from]).to eq(:closed)
      expect(changes.last[:to]).to eq(:open)
    end

    it 'causes subsequent call to short-circuit with OpenError' do
      breaker.trip!
      expect { breaker.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
    end

    it 'causes subsequent call to return fallback when provided' do
      breaker.trip!
      result = breaker.call(fallback: -> { :queued }) { 42 }
      expect(result).to eq(:queued)
    end

    it 'increments rejected_count on subsequent short-circuited calls' do
      breaker.trip!
      2.times { breaker.call(fallback: -> { :nope }) { 42 } }
      expect(breaker.metrics[:rejected_count]).to eq(2)
    end
  end

  describe '#force_open!' do
    it 'transitions to open and marks the breaker as forced' do
      breaker.force_open!
      expect(breaker.state).to eq(:open)
      expect(breaker.forced?).to be true
    end

    it 'rejects calls with OpenError' do
      breaker.force_open!
      expect { breaker.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
    end

    it 'does not transition to half_open even after the timeout elapses' do
      b = described_class.new(:test, threshold: 3, timeout: 0.1)
      b.force_open!
      sleep 0.15
      expect { b.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
      expect(b.state).to eq(:open)
    end

    it 'returns fallback when provided' do
      breaker.force_open!
      result = breaker.call(fallback: -> { :queued }) { 42 }
      expect(result).to eq(:queued)
    end

    it 'is cleared by reset!' do
      breaker.force_open!
      expect(breaker.forced?).to be true
      breaker.reset!
      expect(breaker.forced?).to be false
      expect(breaker.state).to eq(:closed)
    end
  end

  describe '#force_closed!' do
    it 'transitions to closed and marks the breaker as forced' do
      breaker.trip!
      breaker.force_closed!
      expect(breaker.state).to eq(:closed)
      expect(breaker.forced?).to be true
    end

    it 'accepts calls even after threshold failures' do
      breaker.force_closed!
      5.times do
        breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      end
      expect(breaker.state).to eq(:closed)
      expect(breaker.call { :ok }).to eq(:ok)
    end

    it 'is cleared by reset!' do
      breaker.force_closed!
      expect(breaker.forced?).to be true
      breaker.reset!
      expect(breaker.forced?).to be false
      expect(breaker.state).to eq(:closed)
    end
  end
end
