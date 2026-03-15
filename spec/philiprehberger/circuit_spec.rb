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

    def open_circuit(brk)
      3.times do
        brk.call { raise StandardError } rescue nil # rubocop:disable Style/RescueModifier
      end
    end
  end
end
