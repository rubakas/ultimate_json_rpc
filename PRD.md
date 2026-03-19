# PRD — Reclamo Future Requirements

> Product Requirements Document for Reclamo, a network-agnostic Ruby gem
> that exposes Ruby objects through JSON-RPC 2.0.
>
> Current version: 0.2.0 | Ruby >= 3.2 | 26 items — 25 done, 1 pending
> (3 P0 ✓, 8 P1 — 7 done, 10 P2 ✓, 5 P3 ✓)

---

## Delivered (for context)

**v0.1.0** — JSON-RPC 2.0 server, `expose`/`expose_method`, middleware, `rpc.discover`, batch requests, `freeze`, `to_proc`, `only:/except:` filtering, method descriptions, service metadata, test helpers.

**v0.2.0** — `InvalidParams` error class, callable objects in `expose_method`, `empty?`, descriptive error messages, immutable request params, `expose_errors` flag, dangerous method denylist, security hardening.

**Unreleased** — Method-level middleware (`only:/except:` on `use`), Rack adapter, stdio adapter, OpenRPC 1.3.2 schema, instrumentation hooks, request timeout, return type annotations, method deprecation markers, richer test helpers, parameter validation with JSON Schema types, concurrent batch execution, error catalog, custom JSON serializer.

---

## Priority Legend

- **P0** — Foundation: unblocks downstream features
- **P1** — High: drives adoption and real-world usability
- **P2** — Medium: valuable but not blocking other work
- **P3** — Low: nice-to-have, can wait

Items within each tier are ordered by dependency (no-dependency items first, then items whose dependencies are in earlier tiers).

---

## P0 — Foundation

- [x] **OpenRPC schema generation**
  Extend `rpc.discover` to return a full [OpenRPC](https://open-rpc.org/) document. The current response already includes method names, params, and descriptions — OpenRPC formalizes this into a machine-readable spec enabling automatic client generation, interactive docs, and cross-language tooling.
  *Depends on: nothing (builds on existing `rpc.discover`).*

- [x] **Method-level middleware**
  Allow middleware to target specific methods or namespaces: `server.use(only: ["admin.*"]) { |req, nxt| ... }` or `server.use(except: ["ping"]) { ... }`, mirroring the `only:/except:` pattern from `expose`. Enables scoped auth, rate limiting, and logging without global middleware overhead.
  *Depends on: nothing (extends existing middleware chain).*

- [x] **Built-in Rack adapter**
  Ship `Reclamo::Transport::Rack` — a thin Rack app handling Content-Type, HTTP status codes (200/204), and error responses for non-POST requests. Eliminates the boilerplate lambda currently shown in the README.
  *Depends on: nothing.*

---

## P1 — High Priority

Schema & discovery:

- [x] **Parameter validation (JSON Schema)**
  Allow methods to declare parameter schemas validated before dispatch. Return `InvalidParams` (-32602) with descriptive messages on mismatch. Schemas feed into `rpc.discover` / OpenRPC output. Declared via `expose_method("add", params_schema: { ... })` or inferred from Ruby signatures with optional type hints.
  *Depends on: nothing (enhances OpenRPC when both are present, but works standalone).*

- [x] **Return type annotations**
  Let methods declare their return type for discovery metadata: `expose_method("add", returns: { type: "number" })`. Purely informational — no runtime enforcement. Feeds into OpenRPC output and enables richer client generation.
  *Depends on: nothing (enhances OpenRPC when both are present).*

Reliability & performance:

- [x] **Structured logging / instrumentation hooks**
  Lifecycle callbacks (`on_request`, `on_response`, `on_error`) emitting structured data (method name, duration, error code, request id). Dedicated hooks are cleaner than middleware for observability — they can't accidentally swallow errors or alter the response.
  *Depends on: nothing.*

- [x] **Request timeout**
  Configurable per-server (and optionally per-method) timeout so a single slow handler can't block the server. Dedicated error code in the server-error range (-32000..-32099).
  *Depends on: nothing.*

- [x] **Concurrent batch execution**
  Process batch items concurrently via thread pool (opt-in: `concurrent_batches: true`). Current sequential execution is a bottleneck for I/O-bound handlers. Should respect `max_batch_size` and pair well with request timeout.
  *Depends on: nothing (benefits from request timeout to cap runaway items).*

Adoption & integration:

- [x] **Richer test helpers**
  Add `assert_rpc_success(response, expected)`, `assert_rpc_error(response, code:)`, and `assert_rpc_notification(server, method, params:)` to the optional `reclamo/test_helpers` module.
  *Depends on: nothing.*

- [x] **stdio adapter**
  Ship `Reclamo::Transport::Stdio` — a run loop reading JSON-RPC from `$stdin`, writing responses to `$stdout`. Adds signal handling, graceful shutdown, and proper buffering over the manual loop in the README. Critical path for MCP compatibility.
  *Depends on: nothing.*

- [ ] **Rails integration (Railtie)**
  Ship `reclamo-rails` (or built-in Railtie) that mounts a server at a configurable route, auto-discovers service objects, integrates with Rails logger, and respects code reloading in development.
  *Depends on: Rack adapter (P0).*

---

## P2 — Medium Priority

Discovery & metadata:

- [x] **Method deprecation markers**
  Mark methods as deprecated in discovery metadata (`deprecated: true` or `deprecated: "Use add_v2 instead"`). Deprecated methods still work but appear flagged in `rpc.discover` / OpenRPC output.
  *Depends on: nothing (enhances `rpc.discover`).*

- [x] **Error catalog**
  A registry for application-specific error codes and their meanings: `server.register_error(42, "InsufficientFunds", "Account balance too low")`. Registered errors appear in `rpc.discover` output so consumers know which error codes to expect.
  *Depends on: nothing (enhances `rpc.discover`).*

Server configuration:

- [x] **Custom JSON serializer**
  Allow swapping the JSON encoder/decoder (e.g., `Oj`, `yajl-ruby`) via `Reclamo::Server.new(json: Oj)`. The gem currently hard-codes `JSON.parse` / `JSON.generate`.
  *Depends on: nothing.*

- [x] **Versioned API support**
  Run multiple API versions side by side via version prefix (`v1.add`, `v2.add`) or negotiation. Important for long-lived services evolving without breaking consumers.
  *Supported via namespaces: `expose(CalcV1, namespace: "v1")`. See examples/multi_namespace.rb.*

Transport & integration:

- [x] **WebSocket integration guide / adapter**
  Reference adapter or documented pattern for running Reclamo over WebSockets (e.g., `faye-websocket`, `AnyCable`). WebSocket is the second most common JSON-RPC transport after HTTP.
  *Depends on: nothing (gem is already transport-agnostic).*

- [x] **MCP (Model Context Protocol) compatibility**
  Translation layer mapping MCP tool definitions to Reclamo methods and vice versa. JSON-RPC is already MCP's wire protocol — the gap is mainly schema mapping and the stdio transport convention.
  *Depends on: stdio adapter (P1), OpenRPC schema generation (P0).*

Security & middleware:

- [x] **Method-level access control / authorization**
  Declarative way to require roles or permissions per method: `server.authorize("admin.*") { |req| req.context[:role] == :admin }`.
  *Depends on: method-level middleware (P0).*

- [x] **Built-in rate-limiting middleware**
  Optional `Reclamo::Middleware::RateLimit` with token-bucket or sliding-window algorithm, keyed by caller identity from `request.context`.
  *Depends on: method-level middleware (P0) for per-method limits.*

Observability:

- [x] **Structured logging interface**
  Logger-agnostic structured logging built on instrumentation hooks. Log method name, params (redactable), duration, and outcome (success/error). Support log-level filtering and pluggable backends (Rails.logger, $stdout, Semantic Logger) without taking an opinion on the logging library.
  *Depends on: instrumentation hooks (P1).*

Testing:

- [x] **Request/response recording for replay testing**
  Optional recorder capturing JSON-RPC exchanges to a file for backward-compatibility and regression testing.
  *Depends on: instrumentation hooks (P1).*

---

## P3 — Low Priority / Future

- [x] **TCP server adapter**
  Simple TCP listener (`Reclamo::Transport::TCP.new(server, port: 4000).start`) for internal microservices using newline-delimited JSON.
  *Depends on: nothing.*

- [x] **Mock server for consumer-driven testing**
  `Reclamo::MockServer` responding with canned responses based on method+params matching. Pairs with OpenRPC for contract testing.
  *Depends on: OpenRPC schema generation (P0).*

- [x] **Per-method profiling**
  Measure and expose per-method dispatch duration. Opt-in profiling hook that collects timing data with aggregation (min/max/avg/p99) for long-running services. Zero overhead when disabled.
  *Depends on: instrumentation hooks (P1).*

- [x] **API documentation generation**
  Generate human-readable HTML or Markdown docs from the OpenRPC schema.
  *Depends on: OpenRPC schema generation (P0).*

- [x] **Usage examples**
  Runnable examples for common integration patterns: basic Rack/Puma server, Rails controller integration, MCP server over stdio, multi-namespace composition, error handling patterns, and testing patterns. Examples are the fastest path to adoption.
  *Depends on: Rack adapter (P0), Rails integration (P1), MCP compatibility (P2).*

---

## Dependency Graph

```
                    ┌──► Mock server (P3)
OpenRPC (P0) ──────┼──► API docs (P3)
       ▲            └──► MCP compat (P2) ──► Usage examples (P3)
       :                      ▲
  [enhances]                  │
       :                      │
Param valid (P1)    stdio adapter (P1)
Return types (P1)

Method-level MW (P0) ──► Access control (P2)
                    └──► Rate limiting MW (P2)

Rack adapter (P0) ─────► Rails integration (P1) ──► Usage examples (P3)

Instrumentation (P1) ──► Structured logging (P2)
                    ├──► Per-method profiling (P3)
                    └──► Replay recording (P2)
```

*Solid arrows (──►) = hard dependency. Dotted (:) = enhances but doesn't block.*

---

## Out of Scope

- **Built-in authentication** — Reclamo provides hooks and middleware; auth strategy is the caller's domain.
- **Transport-layer concerns** — TLS, connection pooling, reconnection belong to the transport layer.
- **Client library** — Reclamo is server-side only. A JSON-RPC client is a separate project.
- **Database / ORM integration** — persistence is the handler's responsibility.
