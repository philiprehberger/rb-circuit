# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.9] - 2026-03-31

### Changed
- Standardize README badges, support section, and license format

## [0.2.8] - 2026-03-26

### Changed
- Add Sponsor badge to README
- Fix License section format


## [0.2.7] - 2026-03-24

### Changed
- Expand test coverage to 55+ examples covering edge cases and state transitions

## [0.2.6] - 2026-03-24

### Fixed
- Remove inline comments from Development section to match template

## [0.2.5] - 2026-03-23

### Fixed
- Standardize README/CHANGELOG to match template guide

## [0.2.4] - 2026-03-22

### Changed
- Update rubocop configuration for Windows compatibility

## [0.2.3] - 2026-03-21

### Fixed
- Standardize Installation section in README

## [0.2.2] - 2026-03-18

### Changed
- Revert gemspec to single-quoted strings per RuboCop default configuration

## [0.2.1] - 2026-03-18

### Fixed
- Fix RuboCop Style/StringLiterals violations in gemspec

## [0.2.0] - 2026-03-17

### Added
- Fallback support: `breaker.call(fallback: -> { cached }) { api_call }` returns fallback when circuit is open
- Half-open concurrency limit: `half_open_requests:` option controls probe request count in half-open state
- Metrics: `breaker.metrics` returns success/failure/rejected counters and state change log
- Exponential backoff timeout: `timeout_strategy: :exponential` with `base_timeout:` and `max_timeout:` options
- Reset callback: `breaker.on_reset { |from, to| ... }` fires on every state transition

### Changed
- Extracted Metrics, Callbacks, Backoff, and Execution modules for maintainability

## [0.1.2] - 2026-03-16

### Changed
- Add License badge to README
- Add bug_tracker_uri to gemspec

## [0.1.1] - 2026-03-15

## [0.1.0] - 2026-03-15

### Added
- Initial release
- Three-state circuit breaker (closed open half-open)
- Configurable failure thresholds and timeout
- Error class filtering
- Event callbacks for state transitions
