# philiprehberger-circuit

[![Tests](https://github.com/philiprehberger/rb-circuit/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-circuit/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-circuit.svg)](https://rubygems.org/gems/philiprehberger-circuit)
[![License](https://img.shields.io/github/license/philiprehberger/rb-circuit)](LICENSE)

Minimal circuit breaker with configurable thresholds, error filtering, and exponential backoff

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-circuit"
```

Or install directly:

```bash
gem install philiprehberger-circuit
```

## Usage

```ruby
require "philiprehberger/circuit"

breaker = Philiprehberger::Circuit::Breaker.new(:payment_api, threshold: 5, timeout: 30)

breaker.call do
  PaymentGateway.charge(amount)
end
# After 5 failures -> circuit opens -> raises OpenError for 30s
# After 30s -> half-open -> allows one probe request
```

### Fallback

Return a fallback value when the circuit is open instead of raising:

```ruby
breaker.call(fallback: -> { :queued }) do
  PaymentGateway.charge(amount)
end
```

### Error Filtering

```ruby
breaker = Philiprehberger::Circuit::Breaker.new(:api, error_classes: [Net::TimeoutError, Net::OpenTimeout])
```

### Half-Open Control

Limit the number of probe requests allowed in half-open state:

```ruby
breaker = Philiprehberger::Circuit::Breaker.new(:api, half_open_requests: 2)
# Only 2 requests pass through in half-open; the rest are rejected
```

### Metrics

Access counters for monitoring:

```ruby
breaker.metrics
# => { success_count: 42, failure_count: 3, rejected_count: 7, state_changes: [...] }
```

Each state change entry contains `{ from:, to:, at: }` with the transition timestamp.

### Exponential Backoff

Use exponential backoff for the open-to-half-open timeout:

```ruby
breaker = Philiprehberger::Circuit::Breaker.new(
  :api,
  timeout_strategy: :exponential,
  base_timeout: 10,
  max_timeout: 300
)
# Timeouts double on each consecutive open: 20s, 40s, 80s, ... capped at 300s
# Resets to base_timeout when circuit closes
```

### Event Callbacks

```ruby
breaker.on_open { AlertService.notify("Circuit opened!") }
breaker.on_close { AlertService.notify("Circuit recovered") }
breaker.on_half_open { Logger.info("Circuit probing...") }
```

### Reset Callback

Hook into every state transition for logging or alerting:

```ruby
breaker.on_reset do |from_state, to_state|
  Logger.info("Circuit #{breaker.name} transitioned from #{from_state} to #{to_state}")
end
```

## API

| Method | Description |
|--------|-------------|
| `Breaker.new(name, **opts)` | Create a breaker (see options below) |
| `#call(fallback: nil) { block }` | Execute with circuit protection |
| `#state` | Current state (`:closed`, `:open`, `:half_open`) |
| `#reset!` | Force back to closed |
| `#metrics` | Returns `{ success_count:, failure_count:, rejected_count:, state_changes: [] }` |
| `#on_open { }` | Callback when circuit opens |
| `#on_close { }` | Callback when circuit closes |
| `#on_half_open { }` | Callback when circuit enters half-open |
| `#on_reset { \|from, to\| }` | Callback on every state transition |

### Constructor Options

| Option | Default | Description |
|--------|---------|-------------|
| `threshold:` | `5` | Failures before opening |
| `timeout:` | `30` | Seconds before trying half-open (fixed strategy) |
| `error_classes:` | `[StandardError]` | Exception classes to count |
| `half_open_requests:` | `1` | Max probe requests in half-open |
| `timeout_strategy:` | `:fixed` | `:fixed` or `:exponential` |
| `base_timeout:` | `timeout` | Base timeout for exponential backoff |
| `max_timeout:` | `base * 32` | Max timeout cap for exponential backoff |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
