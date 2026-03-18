# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Reclamo is a Ruby gem that exposes Ruby objects (modules, classes, instances, namespaces) through JSON-RPC 2.0. It is network-agnostic — the gem handles JSON-RPC message parsing, method dispatch, and response serialization, while transport (HTTP, WebSocket, stdio, TCP, etc.) is the caller's responsibility.

Ruby >= 3.2 required.

## Commands

```bash
bin/setup              # Install dependencies
rake test              # Run all tests
rake rubocop           # Run linter
rake                   # Run tests + rubocop (default)
ruby -Ilib:test test/test_reclamo.rb                    # Run a single test file
ruby -Ilib:test test/test_reclamo.rb -n test_method     # Run a single test method
bin/console            # Interactive console with gem loaded
```

## Code Style

- Double quotes for all strings (enforced by RuboCop)
- `frozen_string_literal: true` at the top of every Ruby file
- Target Ruby version: 3.2
- `NewCops: enable` in RuboCop config
- `Style/Documentation` disabled (no doc comments required)

## Structure

### Library

- `lib/reclamo.rb` — main entry point, requires all components
- `lib/reclamo/version.rb` — version constant
- `lib/reclamo/errors.rb` — error codes, ERROR_MESSAGES, all error classes (InvalidRequest, InvalidParams, MethodNotFound, ApplicationError, ServerError)
- `lib/reclamo/request.rb` — JSON-RPC request parsing, validation, immutable attributes
- `lib/reclamo/response.rb` — JSON-RPC response building
- `lib/reclamo/handler.rb` — method registry, dispatch, introspection, callable support, freeze
- `lib/reclamo/server.rb` — public API: expose, handle/call, middleware, rpc.discover, service metadata, freeze
- `sig/reclamo.rbs` — RBS type signatures

### Tests

- `test/test_helper.rb` — test setup, loads support fixtures
- `test/support/fixtures.rb` — shared test fixtures (Calculator, Greeter)
- `test/test_reclamo.rb` — version, constants, error class hierarchy
- `test/test_request.rb` — Request unit tests: validation, notification?, freezing, edge cases
- `test/test_response.rb` — Response module unit tests: success/error structure, data handling
- `test/test_server.rb` — core dispatch, notifications, handle_parsed, callable, edge cases, freeze
- `test/test_handler.rb` — handler unit tests, freeze, param descriptors
- `test/test_errors.rb` — server errors, application errors, server errors, request/param validation
- `test/test_batch.rb` — batch requests
- `test/test_discover.rb` — rpc.discover, descriptions, service info
- `test/test_middleware.rb` — middleware chain, edge cases, request immutability
- `test/test_expose.rb` — expose_method, method filtering, callable objects
- `test/test_spec_conformance.rb` — JSON-RPC 2.0 spec conformance + integration tests
