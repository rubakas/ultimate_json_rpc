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
- `lib/reclamo/request.rb` — JSON-RPC request parsing, validation, deep-frozen immutable attributes, mutable context
- `lib/reclamo/response.rb` — JSON-RPC response building
- `lib/reclamo/handler.rb` — method registry, dispatch, introspection, callable support, dangerous method denylist, param validation, freeze
- `lib/reclamo/server.rb` — public API: expose, handle/call, middleware, rpc.discover, service metadata, max_batch_size, expose_errors, timeout, concurrent_batches, instrumentation hooks, freeze
- `lib/reclamo/rack.rb` — optional Rack adapter (Reclamo::Rack), NOT auto-required
- `lib/reclamo/stdio.rb` — optional stdio adapter (Reclamo::Stdio), NOT auto-required
- `lib/reclamo/logging.rb` — optional structured logging (Reclamo::Logging), NOT auto-required
- `lib/reclamo/test_helpers.rb` — optional test helpers (rpc_call, rpc_notify, rpc_batch), NOT auto-required
- `sig/reclamo.rbs` — RBS type signatures

### Tests

- `test/test_helper.rb` — test setup, loads support fixtures
- `test/support/fixtures.rb` — shared test fixtures (Calculator, Greeter)
- `test/test_reclamo.rb` — version, constants, error class hierarchy
- `test/test_request.rb` — Request unit tests: validation, notification?, freezing, edge cases
- `test/test_response.rb` — Response module unit tests: success/error structure, data handling
- `test/test_server.rb` — core dispatch, notifications, handle_parsed, callable, edge cases, freeze
- `test/test_handler.rb` — handler unit tests, freeze, param descriptors, dangerous methods
- `test/test_error_catalog.rb` — error catalog: register_error, discover output, freeze, validation
- `test/test_errors.rb` — server errors, application errors, server errors, request/param validation, expose_errors option
- `test/test_authorize.rb` — method-level authorization: patterns, globs, context, custom codes, denial
- `test/test_batch.rb` — batch requests, batch size limits
- `test/test_concurrent_batch.rb` — concurrent batch execution: threading, order, timeout, middleware, hooks
- `test/test_custom_json.rb` — custom JSON serializer: parse, generate, errors, batch, discover
- `test/test_discover.rb` — rpc.discover, descriptions, service info
- `test/test_middleware.rb` — middleware chain, edge cases, request immutability
- `test/test_method_level_middleware.rb` — scoped middleware: only/except filtering, glob patterns, chain ordering
- `test/test_rack.rb` — Rack adapter: HTTP methods, status codes, content types, edge cases
- `test/test_stdio.rb` — stdio adapter: line processing, notifications, signals, empty lines
- `test/test_hooks.rb` — instrumentation hooks: on_request, on_response, on_error, edge cases
- `test/test_timeout.rb` — request timeout: slow handlers, error codes, notifications, hook integration
- `test/test_deprecation.rb` — method deprecation markers: boolean, string, expose hash, namespace, freeze
- `test/test_logging.rb` — structured logging: levels, duration, method names, errors, chaining
- `test/test_expose.rb` — expose_method, method filtering, callable objects
- `test/test_param_validation.rb` — parameter validation: type checking, enum, positional/keyword, expose, discover, edge cases
- `test/test_spec_conformance.rb` — JSON-RPC 2.0 spec conformance + integration tests
- `test/test_test_helpers.rb` — TestHelpers module tests
