# PRD — Reclamo Future Requirements

> Product Requirements Document for Reclamo, a network-agnostic Ruby gem
> that exposes Ruby objects through JSON-RPC 2.0.
>
> Current version: 0.2.0 | Ruby >= 3.2

---

## Priority Legend

- **P0** — Foundation: must ship before the next features can build on them
- **P1** — High: drives adoption and real-world usability
- **P2** — Medium: valuable but not blocking other work
- **P3** — Low: nice-to-have, can wait

Items within each tier are ordered by dependency (earlier items unblock later ones).

---

## P0 — Foundation

- [ ] **OpenRPC schema generation**
  Extend `rpc.discover` to return a full [OpenRPC](https://open-rpc.org/) document. The current discover response already includes method names, params, and descriptions — OpenRPC formalizes this into a widely adopted, machine-readable specification. This enables automatic client generation, interactive documentation, and cross-language tooling.
  *Depends on: nothing (builds on existing `rpc.discover`).*

- [ ] **Method-level middleware**
  Allow middleware to target specific methods or namespaces instead of running on every request. Common use case: apply authentication only to write methods, or rate-limit only expensive operations. Could take the form of `server.use(only: ["admin.*"]) { |req, nxt| ... }` or `server.use(except: ["ping"]) { ... }`, mirroring the `only:/except:` pattern already used in `expose`.
  *Depends on: nothing (extends existing middleware chain).*

- [ ] **Built-in Rack adapter**
  Ship `Reclamo::Rack` — a thin Rack app wrapper that handles Content-Type negotiation, HTTP status codes (200 for responses, 204 for notifications), and proper error responses for non-POST requests. The README already shows a manual Rack lambda; a first-class adapter eliminates boilerplate and ensures correct behavior.
  *Depends on: nothing.*

---

## P1 — High Priority

- [ ] **Structured logging / instrumentation hooks**
  Provide lifecycle callbacks (`on_request`, `on_response`, `on_error`) that emit structured data (method name, duration, error code, request id). These hooks give users observability without coupling to a specific logging framework. Middleware can do this today, but dedicated hooks are cleaner and cannot accidentally swallow errors or alter the response.
  *Depends on: nothing.*

- [ ] **Request timeout**
  Add a configurable per-server (and optionally per-method) timeout. Long-running handler methods should be interruptible so a single slow call doesn't block the entire server. Could use `Timeout.timeout` with a dedicated error code in the server-error range.
  *Depends on: nothing.*

- [ ] **Concurrent batch execution**
  Execute batch request items concurrently using Ruby's `Ractor` or thread pool. Current implementation processes batch items sequentially. For I/O-bound handlers, parallel execution can dramatically reduce batch latency. Should be opt-in (`concurrent_batches: true` or a concurrency strategy object).
  *Depends on: nothing (but benefits from request timeout to cap runaway items).*

- [ ] **Richer test helpers**
  Add assertion helpers: `assert_rpc_success(response, expected)`, `assert_rpc_error(response, code:)`, `assert_rpc_notification(server, method, params:)`. Reduce boilerplate in test suites and make failure messages more informative. Keep them in the optional `reclamo/test_helpers` require so they don't pollute production.
  *Depends on: nothing.*

- [ ] **Rails integration (Railtie)**
  Ship `reclamo-rails` (or a built-in Railtie) that mounts a Reclamo server at a configurable route, auto-discovers service objects, integrates with Rails logger, and respects Rails reloading in development. This is the highest-leverage integration for Ruby adoption.
  *Depends on: Rack adapter (P0).*

---

## P2 — Medium Priority

- [ ] **Method-level access control / authorization**
  A declarative way to mark methods as requiring specific roles or permissions. Could be a DSL on the server (`server.authorize("admin.*") { |req| req.context[:role] == :admin }`) or metadata on `expose` (`expose(Admin, authorize: :admin_role)`). Cleaner than hand-rolling auth in middleware for every project.
  *Depends on: method-level middleware (P0) for the filtering mechanism.*

- [ ] **Versioned API support**
  Allow running multiple API versions side by side. A version prefix (`v1.add`, `v2.add`) or a version negotiation header lets clients specify which version they target. Important for long-lived services that evolve without breaking existing consumers.
  *Depends on: nothing, but design should consider namespace interaction.*

- [ ] **WebSocket integration guide / adapter**
  Provide a reference adapter or documented pattern for running Reclamo over WebSockets (e.g., with `faye-websocket` or `AnyCable`). WebSocket is the second most common transport after HTTP for JSON-RPC. A working example lowers the barrier to adoption.
  *Depends on: nothing (the gem is already transport-agnostic).*

- [ ] **Built-in rate-limiting middleware**
  Ship an optional `Reclamo::Middleware::RateLimit` that can be dropped in with `server.use(Reclamo::Middleware::RateLimit.new(max: 100, per: 60))`. Basic token-bucket or sliding-window algorithm, keyed by a caller-provided identity (from `request.context`).
  *Depends on: method-level middleware (P0) for per-method limits.*

- [ ] **Request/response recording for replay testing**
  An optional recorder that captures JSON-RPC exchanges to a file. Recorded sessions can be replayed in tests to verify backward compatibility or detect regressions after refactoring. Useful for integration testing without standing up a full server.
  *Depends on: instrumentation hooks (P1) for capture points.*

---

## P3 — Low Priority / Future

- [ ] **stdio adapter**
  Ship `Reclamo::Stdio` — a run loop that reads JSON-RPC messages from `$stdin` and writes responses to `$stdout`, one message per line. Useful for CLI tools, language-server-style integrations, and MCP (Model Context Protocol) servers. The README shows a manual loop; a first-class adapter adds signal handling, graceful shutdown, and proper buffering.
  *Depends on: nothing.*

- [ ] **TCP server adapter**
  A simple TCP listener (`Reclamo::TCP.new(server, port: 4000).start`) for environments where HTTP overhead is unnecessary. Newline-delimited JSON over TCP is a common pattern for internal microservices.
  *Depends on: nothing.*

- [ ] **Mock server for consumer-driven testing**
  A `Reclamo::MockServer` that responds with canned responses based on method+params matching. Lets API consumers write tests without depending on the real service. Pairs well with OpenRPC schemas (P0) for contract testing.
  *Depends on: OpenRPC schema generation (P0) for schema-driven mocking.*

- [ ] **API documentation generation**
  Generate human-readable HTML or Markdown documentation from the OpenRPC schema. Could integrate with YARD or standalone.
  *Depends on: OpenRPC schema generation (P0).*

- [ ] **MCP (Model Context Protocol) compatibility layer**
  Provide a translation layer or adapter that maps MCP tool definitions to Reclamo methods and vice versa. As LLM tool-use grows, being MCP-compatible makes Reclamo servers usable as AI agent tools with no extra glue code.
  *Depends on: stdio adapter (P3), OpenRPC schema generation (P0).*

---

## Dependency Graph (summary)

```
OpenRPC (P0) ──────────► Mock server (P3)
                 ├─────► API docs generation (P3)
                 └─────► MCP compatibility (P3)

Method-level middleware (P0) ──► Access control (P2)
                           └──► Rate limiting middleware (P2)

Rack adapter (P0) ──► Rails integration (P1)

Instrumentation hooks (P1) ──► Request/response recording (P2)

stdio adapter (P3) ──► MCP compatibility (P3)
```

---

## Out of Scope

These are explicitly **not** planned:

- **Built-in authentication** — Reclamo provides hooks and middleware; auth strategy is the caller's domain.
- **Transport-layer concerns** — TLS, connection pooling, reconnection logic belong to the transport layer, not this gem.
- **Client library** — Reclamo is a server-side gem. A JSON-RPC client is a separate project.
- **Database or ORM integration** — Reclamo dispatches calls to Ruby objects; persistence is the handler's responsibility.
