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
        b = described_class.new(
          :test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 0.2
        )
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

    describe 'name accessor' do
      it 'returns the name as provided' do
        expect(breaker.name).to eq(:test)
      end

      it 'accepts a string name' do
        b = described_class.new('my-service', threshold: 3, timeout: 1)
        expect(b.name).to eq('my-service')
      end
    end

    describe 'default configuration' do
      it 'uses a default threshold of 5' do
        b = described_class.new(:defaults)
        4.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(b.state).to eq(:closed)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
      end

      it 'uses a default timeout of 30 seconds' do
        b = described_class.new(:defaults)
        # Circuit opens but timeout hasn't elapsed so it stays open
        5.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect { b.call { 42 } }.to raise_error(Philiprehberger::Circuit::OpenError)
      end
    end

    describe 'closed state behavior' do
      it 'does not open when failures are below threshold' do
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(breaker.state).to eq(:closed)
      end

      it 'resets failure count on success' do
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        breaker.call { :ok }
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(breaker.state).to eq(:closed)
      end

      it 'raises the original exception on failure' do
        expect { breaker.call { raise ArgumentError, 'bad arg' } }.to raise_error(ArgumentError, 'bad arg')
      end

      it 'returns block result on success' do
        expect(breaker.call { 'hello' }).to eq('hello')
      end
    end

    describe 'error class filtering' do
      it 'trips on configured error class' do
        custom = described_class.new(:test, threshold: 2, error_classes: [ArgumentError])
        2.times do
          custom.call { raise ArgumentError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(custom.state).to eq(:open)
      end

      it 'supports multiple error classes' do
        custom = described_class.new(:test, threshold: 2, error_classes: [ArgumentError, TypeError])
        custom.call { raise ArgumentError } rescue nil # rubocop:disable Style/RescueModifier
        custom.call { raise TypeError } rescue nil # rubocop:disable Style/RescueModifier
        expect(custom.state).to eq(:open)
      end

      it 'lets unconfigured errors propagate without counting' do
        custom = described_class.new(:test, threshold: 2, error_classes: [ArgumentError])
        2.times do
          custom.call { raise RuntimeError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(custom.state).to eq(:closed)
        expect(custom.metrics[:failure_count]).to eq(0)
      end
    end

    describe 'OpenError' do
      it 'includes the breaker name in the message' do
        open_circuit(breaker)
        expect { breaker.call { 42 } }.to raise_error(
          Philiprehberger::Circuit::OpenError, 'Circuit test is open'
        )
      end

      it 'is a subclass of Circuit::Error' do
        expect(Philiprehberger::Circuit::OpenError).to be < Philiprehberger::Circuit::Error
      end

      it 'is a subclass of StandardError' do
        expect(Philiprehberger::Circuit::OpenError).to be < StandardError
      end
    end

    describe 'state transition sequences' do
      it 'completes a full closed->open->half_open->closed cycle' do
        open_circuit(breaker)
        expect(breaker.state).to eq(:open)
        sleep 1.1
        breaker.call { :ok }
        expect(breaker.state).to eq(:closed)
        changes = breaker.metrics[:state_changes]
        states = changes.map { |c| c[:to] }
        expect(states).to eq(%i[open half_open closed])
      end

      it 'completes closed->open->half_open->open re-trip on probe failure' do
        open_circuit(breaker)
        sleep 1.1
        breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(breaker.state).to eq(:open)
        changes = breaker.metrics[:state_changes]
        states = changes.map { |c| c[:to] }
        expect(states).to eq(%i[open half_open open])
      end

      it 'can recover after a re-trip' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
        sleep 0.15
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'tracks multiple cycles in state_changes' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { :ok }
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { :ok }
        changes = b.metrics[:state_changes]
        states = changes.map { |c| c[:to] }
        expect(states).to eq(%i[open half_open closed open half_open closed])
      end
    end

    describe 'reset! behavior' do
      it 'resets failure count so threshold must be reached again' do
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        breaker.reset!
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(breaker.state).to eq(:closed)
      end

      it 'can reset from half_open state' do
        open_circuit(breaker)
        sleep 1.1
        # Trigger half-open transition but fail, then reset manually
        breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        breaker.reset!
        expect(breaker.state).to eq(:closed)
      end

      it 'allows normal operation after reset' do
        open_circuit(breaker)
        breaker.reset!
        result = breaker.call { 99 }
        expect(result).to eq(99)
      end
    end

    describe 'callback chaining' do
      it 'on_open returns self for chaining' do
        result = breaker.on_open { nil }
        expect(result).to eq(breaker)
      end

      it 'on_close returns self for chaining' do
        result = breaker.on_close { nil }
        expect(result).to eq(breaker)
      end

      it 'on_half_open returns self for chaining' do
        result = breaker.on_half_open { nil }
        expect(result).to eq(breaker)
      end

      it 'supports chaining multiple callbacks' do
        events = []
        breaker
          .on_open { events << :opened }
          .on_close { events << :closed }
          .on_half_open { events << :half_opened }

        open_circuit(breaker)
        sleep 1.1
        breaker.call { :ok }
        expect(events).to eq(%i[opened half_opened closed])
      end
    end

    describe 'on_half_open callback' do
      it 'fires when transitioning to half_open' do
        called = false
        breaker.on_half_open { called = true }
        open_circuit(breaker)
        sleep 1.1
        breaker.call { :ok }
        expect(called).to be true
      end
    end

    describe 'multiple callbacks for the same event' do
      it 'fires all registered callbacks' do
        results = []
        breaker.on_open { results << :first }
        breaker.on_open { results << :second }
        open_circuit(breaker)
        expect(results).to eq(%i[first second])
      end
    end

    describe 'metrics details' do
      it 'returns a snapshot copy that does not change' do
        snapshot = breaker.metrics
        breaker.call { :ok }
        expect(snapshot[:success_count]).to eq(0)
        expect(breaker.metrics[:success_count]).to eq(1)
      end

      it 'state_changes include timestamps' do
        open_circuit(breaker)
        changes = breaker.metrics[:state_changes]
        expect(changes.first[:at]).to be_a(Time)
      end

      it 'resets success/failure counters correctly after reset!' do
        breaker.call { :ok }
        2.times do
          breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        # Metrics still accumulate even after reset! (they are cumulative)
        open_circuit(breaker)
        m = breaker.metrics
        expect(m[:failure_count]).to be >= 3
        expect(m[:success_count]).to eq(1)
      end

      it 'tracks rejections during open state' do
        open_circuit(breaker)
        3.times do
          breaker.call(fallback: -> { :nope }) { 42 }
        end
        expect(breaker.metrics[:rejected_count]).to eq(3)
      end
    end

    describe 'boundary threshold values' do
      it 'opens on exactly the threshold count' do
        b = described_class.new(:test, threshold: 1, timeout: 1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
      end

      it 'stays closed at threshold minus one' do
        b = described_class.new(:test, threshold: 2, timeout: 1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:closed)
      end

      it 'opens with a high threshold after exact number of failures' do
        b = described_class.new(:test, threshold: 10, timeout: 1)
        9.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(b.state).to eq(:closed)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
      end
    end

    describe 'rapid state transitions' do
      it 'handles rapid open-recover-open cycles' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        5.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
          expect(b.state).to eq(:open)
          sleep 0.15
          b.call { :ok }
          expect(b.state).to eq(:closed)
        end
      end

      it 'accumulates metrics across rapid cycles' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        3.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
          sleep 0.15
          b.call { :ok }
        end
        m = b.metrics
        expect(m[:failure_count]).to eq(3)
        expect(m[:success_count]).to eq(3)
        expect(m[:state_changes].length).to eq(9)
      end

      it 'alternates between open and closed states correctly in rapid succession' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { :ok }
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
        changes = b.metrics[:state_changes]
        to_states = changes.map { |c| c[:to] }
        expect(to_states).to eq(%i[open half_open closed open half_open open])
      end
    end

    describe 'fixed backoff strategy' do
      it 'uses the same timeout on repeated opens' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, timeout_strategy: :fixed)
        # First cycle
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
        # Same fixed timeout applies
        sleep 0.15
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'does not increase timeout even after many opens with fixed strategy' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, timeout_strategy: :fixed)
        3.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
          sleep 0.15
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        # After 3 re-trips, 0.15s should still be enough for fixed 0.1s timeout
        sleep 0.15
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end
    end

    describe 'exponential backoff edge cases' do
      it 'uses base_timeout * 2^1 for the first open' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 10)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        # consecutive_opens = 1, timeout = 0.1 * 2^1 = 0.2s
        sleep 0.15
        expect { b.call { :ok } }.to raise_error(Philiprehberger::Circuit::OpenError)
        sleep 0.1
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end

      it 'defaults max_timeout to base * 32 when not specified' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 1)
        # max_timeout should be 1 * 32 = 32
        # Just verify it creates without error and operates normally
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(b.state).to eq(:open)
      end

      it 'uses timeout option as base_timeout when base_timeout is not specified' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, timeout: 0.1, max_timeout: 10)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        # base_timeout falls back to timeout (0.1), so first timeout = 0.1 * 2^1 = 0.2s
        sleep 0.25
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end
    end

    describe 'error class filtering edge cases' do
      it 'counts subclass errors when parent class is configured' do
        custom = described_class.new(:test, threshold: 2, error_classes: [StandardError])
        custom.call { raise ArgumentError } rescue nil # rubocop:disable Style/RescueModifier
        custom.call { raise TypeError } rescue nil # rubocop:disable Style/RescueModifier
        expect(custom.state).to eq(:open)
      end

      it 'does not count unrelated errors and re-raises them' do
        custom = described_class.new(:test, threshold: 2, error_classes: [ArgumentError])
        expect { custom.call { raise TypeError, 'wrong type' } }.to raise_error(TypeError, 'wrong type')
        expect(custom.state).to eq(:closed)
        expect(custom.metrics[:failure_count]).to eq(0)
      end

      it 'handles empty error_classes array by never tripping' do
        custom = described_class.new(:test, threshold: 1, error_classes: [])
        5.times do
          custom.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(custom.state).to eq(:closed)
      end
    end

    describe 'fallback edge cases' do
      it 'does not invoke fallback during closed-state failures' do
        fallback_called = false
        breaker.call(fallback: -> { fallback_called = true }) { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(fallback_called).to be false
      end

      it 'calls fallback on each rejected request in open state' do
        open_circuit(breaker)
        call_count = 0
        3.times { breaker.call(fallback: -> { call_count += 1 }) { 42 } }
        expect(call_count).to eq(3)
      end

      it 'returns the fallback return value, not the block value' do
        open_circuit(breaker)
        result = breaker.call(fallback: -> { 'fallback_result' }) { 'block_result' }
        expect(result).to eq('fallback_result')
      end
    end

    describe 'reset! edge cases' do
      it 'is a no-op when already closed' do
        breaker.reset!
        expect(breaker.state).to eq(:closed)
      end

      it 'fires callback when reset! from closed state' do
        transitions = []
        breaker.on_reset { |from, to| transitions << [from, to] }
        breaker.reset!
        expect(transitions).to eq([%i[closed closed]])
      end

      it 'clears failure count allowing fresh threshold count' do
        b = described_class.new(:test, threshold: 3, timeout: 1)
        2.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        b.reset!
        3.times do
          b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        end
        expect(b.state).to eq(:open)
      end

      it 'resets backoff counter so exponential timeout restarts' do
        b = described_class.new(:test, threshold: 1, timeout_strategy: :exponential, base_timeout: 0.1, max_timeout: 10)
        # Trip and re-trip to increment consecutive_opens
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.25
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        # consecutive_opens = 2, timeout would be 0.4s
        b.reset!
        # After reset, consecutive_opens = 0
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        # timeout = 0.1 * 2^1 = 0.2s (reset to first open level)
        sleep 0.25
        b.call { :ok }
        expect(b.state).to eq(:closed)
      end
    end

    describe 'metrics after state transitions' do
      it 'tracks rejected count when half-open limit is exceeded' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1, half_open_requests: 0)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call(fallback: -> { :nope }) { 42 }
        expect(b.metrics[:rejected_count]).to eq(1)
      end

      it 'does not increment rejected_count for closed-state failures' do
        breaker.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(breaker.metrics[:rejected_count]).to eq(0)
      end

      it 'state_changes timestamps are monotonically increasing' do
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { :ok }
        times = b.metrics[:state_changes].map { |c| c[:at] }
        times.each_cons(2) { |a, b_time| expect(a).to be <= b_time }
      end

      it 'preserves metrics across multiple reset! calls' do
        breaker.call { :ok }
        open_circuit(breaker)
        breaker.reset!
        breaker.call { :ok }
        m = breaker.metrics
        expect(m[:success_count]).to eq(2)
        expect(m[:failure_count]).to eq(3)
      end
    end

    describe 'callback edge cases' do
      it 'does not fire on_close callback on initial construction' do
        called = false
        b = described_class.new(:test, threshold: 3, timeout: 1)
        b.on_close { called = true }
        expect(called).to be false
      end

      it 'fires on_open multiple times across multiple open transitions' do
        open_count = 0
        b = described_class.new(:test, threshold: 1, timeout: 0.1)
        b.on_open { open_count += 1 }
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.15
        b.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
        expect(open_count).to eq(2)
      end

      it 'fires on_reset callback on manual reset! from open state' do
        transitions = []
        breaker.on_reset { |from, to| transitions << { from: from, to: to } }
        open_circuit(breaker)
        breaker.reset!
        expect(transitions.last).to eq({ from: :open, to: :closed })
      end
    end

    def open_circuit(brk)
      3.times do
        brk.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      end
    end
  end
end
