# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Method-level middleware: `server.use(only: ["admin.*"])` and `server.use(except: ["ping"])` to scope middleware to specific methods or namespaces, with glob pattern support
- `Reclamo::Rack` built-in Rack adapter: Content-Type handling, 200/204/405 responses, `require "reclamo/rack"` to opt in
- Test assertion helpers: `assert_rpc_success`, `assert_rpc_error`, `assert_rpc_notification` in `reclamo/test_helpers`
- `Reclamo::Stdio` adapter: newline-delimited JSON-RPC over stdin/stdout with signal handling, `require "reclamo/stdio"`
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
- Structured logging: `require "reclamo/logging"` adds `server.log_to(logger, level: :info)` for logger-agnostic observability

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
