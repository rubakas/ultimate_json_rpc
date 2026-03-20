# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

UltimateJsonRpc is a Ruby gem that exposes Ruby objects (modules, classes, instances, namespaces) through JSON-RPC 2.0. It is network-agnostic — the gem handles JSON-RPC message parsing, method dispatch, and response serialization, while transport (HTTP, WebSocket, stdio, TCP, etc.) is the caller's responsibility.

Ruby >= 3.2 required.

## Commands

```bash
bin/setup              # Install dependencies
rake test              # Run all tests
rake rubocop           # Run linter
rake                   # Run tests + rubocop (default)
ruby -Ilib:test test/test_ultimate_json_rpc.rb                    # Run a single test file
ruby -Ilib:test test/test_ultimate_json_rpc.rb -n test_method     # Run a single test method
bin/console            # Interactive console with gem loaded
```

## Code Style

- Double quotes for all strings (enforced by RuboCop)
- `frozen_string_literal: true` at the top of every Ruby file
- Target Ruby version: 3.2
- `NewCops: enable` in RuboCop config
- `Style/Documentation` disabled (no doc comments required)
- Methods with 3 or more arguments must use keyword arguments (positional allowed for the primary subject if natural)

## Structure

### Library

- `lib/ultimate_json_rpc.rb` — main entry point, defines UltimateJsonRpc::Core::Error base class, requires all core components
- `lib/ultimate_json_rpc/version.rb` — version constant
- `lib/ultimate_json_rpc/core/errors.rb` — error codes, ERROR_MESSAGES, all error classes (UltimateJsonRpc::Core::InvalidRequest, InvalidParams, MethodNotFound, ApplicationError, ServerError)
- `lib/ultimate_json_rpc/core/request.rb` — JSON-RPC request parsing, validation, deep-frozen immutable attributes, mutable context (UltimateJsonRpc::Core::Request)
- `lib/ultimate_json_rpc/core/response.rb` — JSON-RPC response building (UltimateJsonRpc::Core::Response)
- `lib/ultimate_json_rpc/core/handler.rb` — method registry, dispatch, introspection, callable support, dangerous method denylist, param validation, freeze (UltimateJsonRpc::Core::Handler)
- `lib/ultimate_json_rpc/server.rb` — public API: expose, handle/call, middleware, rpc.discover, service metadata, max_batch_size, expose_errors, timeout, concurrent_batches, instrumentation hooks, freeze
- `lib/ultimate_json_rpc/transport/rack.rb` — optional Rack adapter (UltimateJsonRpc::Transport::Rack), NOT auto-required
- `lib/ultimate_json_rpc/transport/stdio.rb` — optional stdio adapter (UltimateJsonRpc::Transport::Stdio), NOT auto-required
- `lib/ultimate_json_rpc/transport/tcp.rb` — optional TCP adapter (UltimateJsonRpc::Transport::TCP), NOT auto-required
- `lib/ultimate_json_rpc/transport/websocket.rb` — optional WebSocket adapter (UltimateJsonRpc::Transport::WebSocket), NOT auto-required
- `lib/ultimate_json_rpc/extras/docs.rb` — optional Markdown doc generator (UltimateJsonRpc::Extras::Docs), NOT auto-required
- `lib/ultimate_json_rpc/extras/logging.rb` — optional structured logging (UltimateJsonRpc::Extras::Logging class), NOT auto-required
- `lib/ultimate_json_rpc/extras/mcp.rb` — optional MCP protocol adapter (UltimateJsonRpc::Extras::MCP), NOT auto-required; internally requires transport/stdio
- `lib/ultimate_json_rpc/extras/profiler.rb` — optional per-method profiler (UltimateJsonRpc::Extras::Profiler), NOT auto-required
- `lib/ultimate_json_rpc/extras/rate_limit.rb` — optional rate limiter (UltimateJsonRpc::Extras::RateLimiter class), NOT auto-required
- `lib/ultimate_json_rpc/extras/recorder.rb` — optional exchange recorder (UltimateJsonRpc::Extras::Recorder), NOT auto-required
- `lib/ultimate_json_rpc/extras/test_helpers.rb` — optional test helpers (UltimateJsonRpc::Extras::TestHelpers: rpc_call, rpc_notify, rpc_batch), NOT auto-required
- `sig/ultimate_json_rpc.rbs` — RBS type signatures

### Tests

- `test/test_helper.rb` — test setup, loads support fixtures
- `test/support/fixtures.rb` — shared test fixtures (Calculator, Greeter)
- `test/support/discover_helper.rb` — shared discover test helper
- `test/core/test_ultimate_json_rpc.rb` — version, constants, error class hierarchy
- `test/core/test_request.rb` — Request unit tests: validation, notification?, freezing, edge cases
- `test/core/test_response.rb` — Response module unit tests: success/error structure, data handling
- `test/core/test_handler.rb` — handler unit tests, freeze, param descriptors, dangerous methods
- `test/core/test_errors.rb` — server errors, application errors, server errors, request/param validation, expose_errors option
- `test/test_server.rb` — core dispatch, notifications, handle_parsed, callable, edge cases, freeze
- `test/test_error_catalog.rb` — error catalog: register_error, discover output, freeze, validation
- `test/test_authorize.rb` — method-level authorization: patterns, globs, context, custom codes, denial
- `test/test_batch.rb` — batch requests, batch size limits
- `test/test_concurrent_batch.rb` — concurrent batch execution: threading, order, timeout, middleware, hooks
- `test/test_custom_json.rb` — custom JSON serializer: parse, generate, errors, batch, discover
- `test/test_discover.rb` — rpc.discover, descriptions, service info
- `test/test_middleware.rb` — middleware chain, edge cases, request immutability
- `test/test_method_level_middleware.rb` — scoped middleware: only/except filtering, glob patterns, chain ordering
- `test/test_hooks.rb` — instrumentation hooks: on_request, on_response, on_error, edge cases
- `test/test_timeout.rb` — request timeout: slow handlers, error codes, notifications, hook integration
- `test/test_deprecation.rb` — method deprecation markers: boolean, string, expose hash, namespace, freeze
- `test/test_expose.rb` — expose_method, method filtering, callable objects
- `test/test_param_validation.rb` — parameter validation: type checking, enum, positional/keyword, expose, discover, edge cases
- `test/test_spec_conformance.rb` — JSON-RPC 2.0 spec conformance + integration tests
- `test/transport/test_rack.rb` — Rack adapter: HTTP methods, status codes, content types, edge cases
- `test/transport/test_stdio.rb` — stdio adapter: line processing, notifications, signals, empty lines
- `test/transport/test_tcp.rb` — TCP adapter: requests, multi-client, notifications, stop/running
- `test/transport/test_websocket.rb` — WebSocket adapter: on_message, call with mock socket, notifications
- `test/extras/test_docs.rb` — API doc generation: title, methods, params, returns, deprecation, errors
- `test/extras/test_logging.rb` — structured logging: levels, duration, method names, errors, chaining
- `test/extras/test_mcp.rb` — MCP adapter: initialize, tools/list, tools/call, schemas, namespaces, errors
- `test/extras/test_profiler.rb` — per-method profiling: count, min/max/avg, percentiles, reset, thread safety
- `test/extras/test_rate_limit.rb` — rate limiting: sliding window, per-caller, scoping, thread safety
- `test/extras/test_recorder.rb` — exchange recorder: capture, clear, JSONL output, thread safety, batch
- `test/extras/test_test_helpers.rb` — TestHelpers module tests
