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

### Error handling

Raise `ApplicationError` for custom error codes, or `ServerError` for implementation-defined errors:

```ruby
raise Reclamo::ApplicationError.new(42, "Custom error", { "detail" => "info" })
raise Reclamo::ServerError.new(-32_001, "Server shutting down")
```

Ruby's `ArgumentError` automatically maps to JSON-RPC Invalid params (`-32602`). All other exceptions become Internal error (`-32603`).

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
- **Error handling** — standard JSON-RPC error codes, `ApplicationError`, and `ServerError`
- **Chainable API** — all setup methods return `self`
- **Callable** — `to_proc` enables `requests.map(&server)`
- **Freezable** — `server.freeze` locks configuration after setup

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
