# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `TCP#port` accessor for discovering the bound port at runtime

### Fixed
- RBS type signatures now correctly reflect Core/Extras/Transport namespace structure
- RBS `Server` class no longer declares conditional `include` for `Extras::Logging` and `Extras::RateLimitSupport`
- Recorder `max_exchanges:` and TCP `MAX_LINE_BYTES` added to RBS type signatures
- `Docs#escape_cell` now escapes newlines in Markdown table cells
- Flaky profiler test with timing-dependent percentile assertion

## [0.3.0] - 2026-03-18

### Added
- Method-level middleware: `server.use(only: ["admin.*"])` and `server.use(except: ["ping"])` to scope middleware to specific methods or namespaces, with glob pattern support
- `Reclamo::Transport::Rack` built-in Rack adapter: Content-Type handling, 200/204/405 responses, `require "reclamo/transport/rack"` to opt in
- Test assertion helpers: `assert_rpc_success`, `assert_rpc_error`, `assert_rpc_notification` in `reclamo/test_helpers`
- `Reclamo::Transport::Stdio` adapter: newline-delimited JSON-RPC over stdin/stdout with signal handling, `require "reclamo/transport/stdio"`
- Return type annotations: `returns:` keyword on `expose_method` and `returns:` hash on `expose`, appears in `rpc.discover`
- OpenRPC 1.3.2 schema: `rpc.discover` now returns a full OpenRPC document with `openrpc` version, `info` object, and `result` contentDescriptors
- Instrumentation hooks: `server.on(:request)`, `on(:response)`, `on(:error)` for read-only lifecycle observability with duration timing
- Request timeout: `Server.new(timeout: 5)` wraps dispatch in `Timeout.timeout`, returns `-32001 Request timeout` on expiry
- `RequestTimeout` error class and `REQUEST_TIMEOUT` (-32001) constant
- Method deprecation markers: `deprecated: true` or `deprecated: "Use v2"` on `expose_method` and `expose`, appears in `rpc.discover`
- Parameter validation: `params_schema:` on `expose_method` and `expose` for type and enum validation before dispatch, returns `-32602 Invalid params` on mismatch, schemas appear in `rpc.discover` param descriptors
- Concurrent batch execution: `Server.new(concurrent_batches: true)` processes batch items in parallel using threads
- Error catalog: `server.register_error(code, name, description)` registers application error codes that appear in `rpc.discover` under `components.errors`
- Custom JSON serializer: `Server.new(json: Oj)` to swap JSON encoder/decoder, any object responding to `parse` and `generate`
- Method-level authorization: `server.authorize("admin.*") { |req| req.context[:role] == :admin }` with glob patterns and custom error codes
- Structured logging: `require "reclamo/extras/logging"` adds `server.log_to(logger, level: :info)` for logger-agnostic observability
- Request/response recorder: `require "reclamo/extras/recorder"` provides `Reclamo::Extras::Recorder.new(server)` capturing exchanges for replay testing, with optional JSONL file output
- MCP (Model Context Protocol) adapter: `require "reclamo/extras/mcp"` provides `Reclamo::Extras::MCP.new(server)` for AI tool integration over stdio, mapping methods to MCP tools with schema support
- Rate limiting: `require "reclamo/extras/rate_limit"` adds `server.rate_limit(max:, period:)` with sliding window, per-caller keying, and per-method scoping
- Per-method profiling: `require "reclamo/extras/profiler"` provides `Reclamo::Extras::Profiler.new(server)` collecting count, min/max/avg, and p50/p95/p99 per method
- Mock server: `require "reclamo/extras/mock_server"` provides `Reclamo::Extras::MockServer` with `stub`/`stub_any` for consumer-driven contract testing
- TCP server adapter: `require "reclamo/transport/tcp"` provides `Reclamo::Transport::TCP.new(server, port: 4000)` for newline-delimited JSON-RPC over TCP with multi-client threading
- API documentation generation: `require "reclamo/extras/docs"` provides `Reclamo::Extras::Docs.new(server).to_markdown` generating Markdown from OpenRPC schema
- Usage examples: `examples/` directory with runnable patterns for Rack, MCP, multi-namespace/versioning, error handling, and testing
- WebSocket adapter: `require "reclamo/transport/websocket"` provides `Reclamo::Transport::WebSocket` for JSON-RPC over WebSockets with any Rack-compatible library

### Fixed
- MCP `inputSchema` now always included for zero-parameter tools (MCP spec compliance)
- `handle_parsed` no longer crashes with `TypeError` on Symbol-keyed hashes

### Changed
- `rpc.discover` output restructured: service metadata moved to `info` object (`name` → `info.title`), method `returns` → `result` in OpenRPC contentDescriptor format

## [0.2.0] - 2026-03-18

### Added
- `InvalidParams` error class for explicit -32602 errors from user code
- `expose_method` accepts callable objects (Method, Proc, lambda) as first argument
- `Server#empty?` and `Handler#empty?` convenience methods
- Callable validation: `expose_method` checks that callable responds to `#call`

### Changed
- `MethodNotFound` now has a descriptive Ruby exception message ("Method not found: name")
- `ApplicationError` validates that error code is an Integer
- Request params and id are frozen after construction for immutability
- `ServerError` uses `between?` for range validation (consistency)

## [0.1.0] - 2025-05-01

### Added
- Initial release
- JSON-RPC 2.0 server with `expose`, `expose_method`, and middleware support
- `rpc.discover` built-in introspection
- Batch request handling
- `Server#freeze` for thread-safe immutability
- `Server#call` alias and `#to_proc` for Rack-like usage
- `only:`/`except:` method filtering
- Method descriptions via `descriptions:` option
- Service metadata via `name:` and `version:` options
