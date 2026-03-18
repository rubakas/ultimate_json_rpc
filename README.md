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

### Service discovery

Built-in `rpc.discover` returns method info including parameter details:

```ruby
request = '{"jsonrpc":"2.0","method":"rpc.discover","id":1}'
server.handle(request)
# => '{"jsonrpc":"2.0","result":{"methods":[{"name":"add","params":[...]},{"name":"divide","params":[...]}]},"id":1}'
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
- **Service metadata** — `name:` and `version:` appear in `rpc.discover` responses
- **Positional and keyword params** — arrays map to positional args, objects map to keyword args
- **Service discovery** — built-in `rpc.discover` method with param info
- **Middleware** — `server.use { |request, next_call| ... }` for cross-cutting concerns
- **Scoped middleware** — `only:` / `except:` with glob patterns to target specific methods or namespaces
- **Error handling** — standard JSON-RPC error codes, `ApplicationError`, and `ServerError`
- **Chainable API** — all setup methods return `self`
- **Callable** — `to_proc` enables `requests.map(&server)`
- **Rack adapter** — `Reclamo::Rack.new(server)` for instant HTTP deployment
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

```ruby
require "reclamo"

server = Reclamo::Server.new
server.expose(Calculator)

$stdin.each_line do |line|
  response = server.handle(line)
  $stdout.puts(response) if response
  $stdout.flush
end
```

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
