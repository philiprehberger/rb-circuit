# philiprehberger-circuit

[![Tests](https://github.com/philiprehberger/rb-circuit/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-circuit/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-circuit.svg)](https://rubygems.org/gems/philiprehberger-circuit)

Minimal circuit breaker — three states (closed/open/half-open), configurable thresholds, error class filtering, and event callbacks.

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-circuit"
```

Then run:

```bash
bundle install
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

### With Fallback

```ruby
breaker.call(fallback: -> { :queued }) do
  PaymentGateway.charge(amount)
end
```

### Error Filtering

```ruby
breaker = Philiprehberger::Circuit::Breaker.new(:api, error_classes: [Net::TimeoutError, Net::OpenTimeout])
```

### Event Callbacks

```ruby
breaker.on_open { AlertService.notify("Circuit opened!") }
breaker.on_close { AlertService.notify("Circuit recovered") }
breaker.on_half_open { Logger.info("Circuit probing...") }
```

## API

| Method | Description |
|--------|-------------|
| `Breaker.new(name, threshold: 5, timeout: 30, error_classes: [StandardError])` | Create a breaker |
| `#call(fallback: nil) { block }` | Execute with circuit protection |
| `#state` | Current state (`:closed`, `:open`, `:half_open`) |
| `#reset!` | Force back to closed |
| `#on_open { }` | Callback when circuit opens |
| `#on_close { }` | Callback when circuit closes |
| `#on_half_open { }` | Callback when circuit enters half-open |

## Development

```bash
bundle install
bundle exec rspec      # Run tests
bundle exec rubocop    # Check code style
```

## License

MIT
