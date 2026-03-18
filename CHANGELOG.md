# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Method-level middleware: `server.use(only: ["admin.*"])` and `server.use(except: ["ping"])` to scope middleware to specific methods or namespaces, with glob pattern support
- `Reclamo::Rack` built-in Rack adapter: Content-Type handling, 200/204/405 responses, `require "reclamo/rack"` to opt in

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
