# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::Circuit do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end

  describe Philiprehberger::Circuit::Breaker do
    subject(:breaker) { described_class.new(:test, threshold: 3, timeout: 1) }

    it 'starts in closed state' do
      expect(breaker.state).to eq(:closed)
    end

    it 'executes block and returns result when closed' do
      result = breaker.call { 42 }
      expect(result).to eq(42)
    end

    it 'opens after reaching failure threshold' do
      3.times do
        breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      end
      expect(breaker.state).to eq(:open)
    end

    it 'raises OpenError when open and no fallback' do
      open_circuit(breaker)
      expect { breaker.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
    end

    it 'uses fallback when open' do
      open_circuit(breaker)
      result = breaker.call(fallback: -> { :fallback }) { 42 }
      expect(result).to eq(:fallback)
    end

    it 'transitions to half_open after timeout' do
      open_circuit(breaker)
      sleep 1.1
      breaker.call { 42 }
      expect(breaker.state).to eq(:closed)
    end

    it 'closes on successful half_open call' do
      open_circuit(breaker)
      sleep 1.1
      breaker.call { :ok }
      expect(breaker.state).to eq(:closed)
    end

    it 'reopens on failed half_open call' do
      open_circuit(breaker)
      sleep 1.1
      breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      expect(breaker.state).to eq(:open)
    end

    it 'resets to closed' do
      open_circuit(breaker)
      breaker.reset!
      expect(breaker.state).to eq(:closed)
    end

    it 'only trips on configured error classes' do
      custom = described_class.new(:test, threshold: 3, error_classes: [ArgumentError])
      3.times do
        custom.call { raise RuntimeError } rescue nil # rubocop:disable Style/RescueModifier
      end
      expect(custom.state).to eq(:closed)
    end

    it 'fires on_open callback' do
      called = false
      breaker.on_open { called = true }
      open_circuit(breaker)
      expect(called).to be true
    end

    it 'fires on_close callback' do
      called = false
      breaker.on_close { called = true }
      open_circuit(breaker)
      sleep 1.1
      breaker.call { :ok }
      expect(called).to be true
    end

    describe 'fallback' do
      it 'returns fallback value when circuit is open' do
        open_circuit(breaker)
        result = breaker.call(fallback: -> { :cached }) { raise StandardError }
        expect(result).to eq(:cached)
      end

      it 'does not call fallback when circuit is closed' do
        fallback_called = false
        breaker.call(fallback: -> { fallback_called = true }) { 42 }
        expect(fallback_called).to be false
      end

      it 'returns fallback when half-open slots are exhausted' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, half_open_requests: 0)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.2
        result = b.call(fallback: -> { :rejected }) { 42 }
        expect(result).to eq(:rejected)
      end
    end

    describe 'half-open concurrency limit' do
      it 'defaults to allowing 1 probe request' do
        open_circuit(breaker)
        sleep 1.1
        breaker.call { :ok }
        expect(breaker.state).to eq(:closed)
      end

      it 'rejects excess half-open requests' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, half_open_requests: 1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
        sleep 0.2
        # First call transitions to half-open and uses the 1 allowed slot
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'allows configurable number of probe requests' do
        b = described_class.new(:test, threshold: 2, timeout: 0.1, half_open_requests: 2)
        2.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(b.state).to eq(:open)
        sleep 0.2
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'raises OpenError when half-open limit exceeded and no fallback' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, half_open_requests: 0)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.2
        expect { b.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
      end
    end

    describe 'metrics' do
      it 'returns initial metrics with zero counters' do
        m = breaker.metrics
        expect(m[:success_count]).to eq(0)
        expect(m[:failure_count]).to eq(0)
        expect(m[:rejected_count]).to eq(0)
        expect(m[:state_changes]).to be_empty
      end

      it 'tracks success count' do
        3.times { breaker.call { :ok } }
        expect(breaker.metrics[:success_count]).to eq(3)
      end

      it 'tracks failure count' do
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(breaker.metrics[:failure_count]).to eq(2)
      end

      it 'tracks rejected count when circuit is open' do
        open_circuit(breaker)
        2.times do
          breaker.call(fallback: -> { :nope }) { 42 }
        end
        expect(breaker.metrics[:rejected_count]).to eq(2)
      end

      it 'records state changes' do
        open_circuit(breaker)
        changes = breaker.metrics[:state_changes]
        expect(changes.last[:from]).to eq(:closed)
        expect(changes.last[:to]).to eq(:open)
      end

      it 'records full transition cycle' do
        open_circuit(breaker)
        sleep 1.1
        breaker.call { :ok }
        changes = breaker.metrics[:state_changes]
        states = changes.map { |c| [c[:from], c[:to]] }
        expect(states).to include(%i[closed open])
        expect(states).to include(%i[open half_open])
        expect(states).to include(%i[half_open closed])
      end
    end

    describe 'exponential backoff timeout' do
      it 'uses fixed timeout by default' do
        b = described_class.new(:test, threshold: 1, timeout: 1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 1.1
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'increases timeout exponentially on repeated opens' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 10)
        # First open: timeout = 0.1 * 2^1 = 0.2s
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)

        # Wait long enough for first timeout (0.2s), fail in half-open to re-open
        sleep 0.25
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)

        # Second open: timeout = 0.1 * 2^2 = 0.4s
        # Waiting 0.25s should NOT be enough
        sleep 0.25
        expect { b.call { :ok } }.to raise_error(Philiprehberger::Circuit::OpenError)
      end

      it 'caps timeout at max_timeout' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 0.2)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.25
        # Reopens on failure in half-open
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        # max_timeout is 0.2, even though exponential would be higher
        sleep 0.25
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'resets backoff counter when circuit closes' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 10)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.25
        b.call { :ok }
        expect(b.state).to eq(:closed)
        # After reset, consecutive_opens is 0 again, timeout = base * 2^1 = 0.2s
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.25
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end
    end

    describe 'on_reset callback' do
      it 'fires on every state transition' do
        transitions = []
        breaker.on_reset { |from, to| transitions << [from, to] }
        open_circuit(breaker)
        expect(transitions).to include(%i[closed open])
      end

      it 'fires on close after half-open' do
        transitions = []
        breaker.on_reset { |from, to| transitions << [from, to] }
        open_circuit(breaker)
        sleep 1.1
        breaker.call { :ok }
        expect(transitions).to include(%i[open half_open])
        expect(transitions).to include(%i[half_open closed])
      end

      it 'fires on manual reset' do
        transitions = []
        breaker.on_reset { |from, to| transitions << [from, to] }
        open_circuit(breaker)
        breaker.reset!
        expect(transitions.last).to eq(%i[open closed])
      end

      it 'returns self for chaining' do
        result = breaker.on_reset { |_f, _t| nil }
        expect(result).to eq(breaker)
      end
    end

    def open_circuit(brk)
      3.times do
        brk.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      end
    end
  end
end
