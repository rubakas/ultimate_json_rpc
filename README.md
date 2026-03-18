# Reclamo

Network-agnostic JSON-RPC 2.0 server that exposes Ruby modules, classes, and instances as callable RPC endpoints. Reclamo handles JSON-RPC message parsing, method dispatch, and response serialization — transport (HTTP, WebSocket, stdio, TCP, etc.) is the caller's responsibility.

## Installation

Add to your Gemfile:

```ruby
gem "reclamo"
```

## Usage

```ruby
require "reclamo"

# Define your service
module Calculator
  def self.add(a, b) = a + b
  def self.divide(a, b) = a.to_f / b
end

# Create a server and expose objects
server = Reclamo::Server.new(name: "My API", version: "1.0")
server.expose(Calculator, descriptions: { add: "Add two numbers" })
server.expose(some_instance, namespace: "greeter")

# Handle a JSON-RPC request string, get a JSON-RPC response string
request = '{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'
response = server.handle(request)
# => '{"jsonrpc":"2.0","result":5,"id":1}'
```

### Expose individual methods

```ruby
server.expose_method("double", description: "Double a number") { |n| n * 2 }
server.expose_method("greet") { |name:, greeting: "Hello"| "#{greeting}, #{name}!" }
```

### Chainable API

All setup methods return `self`, and the server is callable via `to_proc`:

```ruby
server = Reclamo::Server.new
  .expose(Calculator, namespace: "calc")
  .expose_method("ping") { "pong" }
  .use { |req, next_call| next_call.call }

# Use to_proc for mapping over requests
responses = json_requests.map(&server)
```

### Return type annotations

Declare return types for discovery metadata (purely informational, no runtime enforcement):

```ruby
server.expose_method("add", returns: { "type" => "number" }) { |a, b| a + b }
server.expose(Calculator, returns: { add: { "type" => "number" } })
```

### Service discovery

Built-in `rpc.discover` returns an [OpenRPC](https://open-rpc.org/) 1.3.2-compatible document:

```ruby
request = '{"jsonrpc":"2.0","method":"rpc.discover","id":1}'
server.handle(request)
# => '{"jsonrpc":"2.0","result":{"openrpc":"1.3.2","info":{"title":"My API","version":"1.0"},"methods":[...]},"id":1}'
```

### Middleware

Add cross-cutting concerns like logging, auth, or rate limiting:

```ruby
server.use do |request, next_call|
  puts "Calling #{request.method_name}"
  result = next_call.call
  puts "Done"
  result
end

# Reject unauthorized calls
server.use do |request, next_call|
  raise Reclamo::ApplicationError.new(403, "Forbidden") unless authorized?(request)

  next_call.call
end
```

Middleware runs in registration order (first registered = outermost wrapper).

#### Scoped middleware

Target specific methods or namespaces with `only:` / `except:`, supporting glob patterns:

```ruby
# Only run for admin namespace methods
server.use(only: ["admin.*"]) do |request, next_call|
  raise Reclamo::ApplicationError.new(403, "Forbidden") unless admin?(request)
  next_call.call
end

# Run for everything except health checks
server.use(except: ["ping", "health"]) do |request, next_call|
  log(request)
  next_call.call
end
```

Middleware can pass data to handlers via `request.context`:

```ruby
server.use do |request, next_call|
  request.context[:user] = authenticate(request)
  next_call.call
end
```

### Instrumentation hooks

Read-only lifecycle hooks for observability — they can't alter responses or swallow errors:

```ruby
server.on(:request)  { |request| puts "→ #{request.method_name}" }
server.on(:response) { |request, result, duration| puts "← #{request.method_name} (#{duration}s)" }
server.on(:error)    { |request, error, duration| log_error(error, method: request.method_name) }
```

Hook errors are rescued and logged via `Kernel.warn`, never breaking dispatch.

### Custom JSON serializer

Swap the JSON encoder/decoder (defaults to stdlib `JSON`):

```ruby
require "oj"
Oj.mimic_JSON
server = Reclamo::Server.new(json: Oj)
```

Any object responding to `parse(string)` and `generate(object)` works.

### Concurrent batches

Opt-in parallel processing for batch requests:

```ruby
server = Reclamo::Server.new(concurrent_batches: true)
# Batch items are processed in parallel using threads
# Respects max_batch_size and request timeout
```

### Request timeout

Set a per-server timeout (in seconds) to prevent slow handlers from blocking:

```ruby
server = Reclamo::Server.new(timeout: 5)
# Handlers exceeding 5 seconds receive a -32001 "Request timeout" error
```

### Parameter validation

Declare parameter schemas to validate incoming params before dispatch:

```ruby
server.expose_method("add", params_schema: {
  a: { "type" => "number" },
  b: { "type" => "number" }
}) { |a, b| a + b }

server.expose(Calculator, params_schema: {
  add: { left: { "type" => "number" }, right: { "type" => "number" } }
})
```

Supported JSON Schema keywords: `type` (`string`, `number`, `integer`, `boolean`, `array`, `object`, `null`) and `enum`. On mismatch, returns `-32602 Invalid params` with a descriptive message. Schemas also appear in `rpc.discover` output.

### Method deprecation

Mark methods as deprecated in discovery metadata (purely informational, no runtime enforcement):

```ruby
server.expose_method("old_add", deprecated: true) { |a, b| a + b }
server.expose_method("old_multiply", deprecated: "Use multiply_v2 instead") { |a, b| a * b }
server.expose(Calculator, deprecated: { add: "Use add_v2" })
```

Deprecated methods still work normally but appear flagged in `rpc.discover` output.

### Structured logging

Logger-agnostic observability via `log_to`:

```ruby
require "reclamo/logging"

server.log_to(Logger.new($stdout))           # logs at INFO by default
server.log_to(Rails.logger, level: :debug)   # custom level
```

Successful responses log at the specified level; errors always log at ERROR.

### Authorization

Declarative access control with glob patterns:

```ruby
server.authorize("admin.*") { |req| req.context[:role] == :admin }
server.authorize("users.delete", code: 1001, message: "Insufficient permissions") do |req|
  req.context[:permissions]&.include?("delete")
end
```

Returns `ApplicationError` (code 403 by default) when the block returns falsy.

### Error catalog

Register application-specific error codes for discovery:

```ruby
server.register_error(42, "InsufficientFunds", "Account balance too low")
server.register_error(43, "AccountLocked")
```

Registered errors appear in `rpc.discover` under `components.errors`, so consumers know which error codes to expect.

### Error handling

Raise `ApplicationError` for custom error codes, or `ServerError` for implementation-defined errors:

```ruby
raise Reclamo::ApplicationError.new(42, "Custom error", { "detail" => "info" })
raise Reclamo::ServerError.new(-32_001, "Server shutting down")
```

Ruby's `ArgumentError` automatically maps to JSON-RPC Invalid params (`-32602`). All other exceptions become Internal error (`-32603`).

### Error visibility

By default, internal error details (exception messages) are hidden from clients:

```ruby
server = Reclamo::Server.new                    # expose_errors: false (default)
# Internal errors return generic "Internal server error" in the data field

server = Reclamo::Server.new(expose_errors: true)
# Internal errors include the actual exception message in the data field
```

`ApplicationError`, `ServerError`, `InvalidParams`, and `MethodNotFound` always expose their details regardless of this setting, since those are intentionally raised by your code.

### Freezing

Lock the server after setup to prevent accidental modifications:

```ruby
server.freeze  # expose, expose_method, use will now raise FrozenError
server.handle(request)  # still works
```

### Features

- **JSON-RPC 2.0** compliant (requests, notifications, batch requests)
- **Expose modules** — singleton methods become RPC methods
- **Expose instances** — public methods become RPC methods
- **Expose blocks** — `server.expose_method("name") { ... }` for standalone methods
- **Namespacing** — `server.expose(obj, namespace: "ns")` makes methods callable as `ns.method_name`
- **Method filtering** — `server.expose(obj, only: [:add])` or `except: [:internal]`
- **Method descriptions** — `descriptions:` hash or `description:` keyword for discovery
- **Return type annotations** — `returns:` hash or keyword for discovery metadata
- **Service metadata** — `name:` and `version:` appear in `rpc.discover` responses
- **Positional and keyword params** — arrays map to positional args, objects map to keyword args
- **Service discovery** — built-in `rpc.discover` returns OpenRPC 1.3.2-compatible schema
- **Middleware** — `server.use { |request, next_call| ... }` for cross-cutting concerns
- **Scoped middleware** — `only:` / `except:` with glob patterns to target specific methods or namespaces
- **Instrumentation hooks** — `on(:request)`, `on(:response)`, `on(:error)` for read-only observability
- **Parameter validation** — `params_schema:` with JSON Schema types and enum constraints
- **Request timeout** — `Server.new(timeout: 5)` prevents slow handlers from blocking
- **Method deprecation** — mark methods as deprecated in discovery metadata
- **Error catalog** — `register_error` documents app error codes in `rpc.discover`
- **Authorization** — `authorize("admin.*") { |req| ... }` for declarative access control
- **Error handling** — standard JSON-RPC error codes, `ApplicationError`, and `ServerError`
- **Error visibility** — `expose_errors: true` to include exception messages in error responses
- **Security** — dangerous methods (eval, system, exec, etc.) are automatically blocked
- **Chainable API** — all setup methods return `self`
- **Callable** — `to_proc` enables `requests.map(&server)`
- **Rack adapter** — `Reclamo::Rack.new(server)` for instant HTTP deployment
- **stdio adapter** — `Reclamo::Stdio.new(server).run` for CLI/MCP-style integrations
- **Test helpers** — `rpc_call`, `assert_rpc_success`, `assert_rpc_error` for cleaner tests
- **Concurrent batches** — `concurrent_batches: true` processes batch items in parallel
- **Custom JSON** — `json: Oj` to swap the JSON encoder/decoder
- **Batch size limit** — `max_batch_size: 100` (default) prevents oversized batch requests
- **Freezable** — `server.freeze` locks configuration after setup

### Transport examples

Reclamo is transport-agnostic. Here are common setups:

#### Rack (HTTP)

Use the built-in Rack adapter:

```ruby
# config.ru
require "reclamo"
require "reclamo/rack"

server = Reclamo::Server.new(name: "My API")
server.expose(Calculator)

run Reclamo::Rack.new(server)
```

`Reclamo::Rack` handles Content-Type, returns 200 for responses, 204 for notifications, and 405 for non-POST requests.

#### stdio

Use the built-in stdio adapter:

```ruby
require "reclamo"
require "reclamo/stdio"

server = Reclamo::Server.new
server.expose(Calculator)

Reclamo::Stdio.new(server).run
```

`Reclamo::Stdio` reads newline-delimited JSON-RPC from stdin, writes responses to stdout, skips empty lines, and handles `SIGINT`/`SIGTERM` for graceful shutdown.

### Pre-parsed input

If you've already parsed the JSON (e.g. from a WebSocket frame), use `handle_parsed` to skip the parse step:

```ruby
data = JSON.parse(raw_json)
response = server.handle_parsed(data)
```

### Test helpers

Reclamo ships with optional test helpers for cleaner assertions:

```ruby
require "reclamo/test_helpers"

class MyTest < Minitest::Test
  include Reclamo::TestHelpers

  def test_addition
    response = rpc_call(server, "add", params: [2, 3])
    assert_rpc_success response, 5
  end

  def test_method_not_found
    response = rpc_call(server, "nonexistent")
    assert_rpc_error response, code: -32_601
  end

  def test_notification
    assert_rpc_notification server, "add", params: [1, 2]
  end
end
```

## Development

```bash
bin/setup       # Install dependencies
rake test       # Run tests
rake rubocop    # Run linter
rake            # Run both
bin/console     # Interactive console
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rubakas/reclamo.
