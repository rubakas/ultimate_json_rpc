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
server = Reclamo::Server.new
server.expose(Calculator)
server.expose(some_instance, namespace: "greeter")

# Handle a JSON-RPC request string, get a JSON-RPC response string
request = '{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'
response = server.handle(request)
# => '{"jsonrpc":"2.0","result":5,"id":1}'
```

### Features

- **JSON-RPC 2.0** compliant (requests, notifications, batch requests)
- **Expose modules** — singleton methods become RPC methods
- **Expose instances** — public methods become RPC methods
- **Namespacing** — `server.expose(obj, namespace: "ns")` makes methods callable as `ns.method_name`
- **Positional and keyword params** — arrays map to positional args, objects map to keyword args
- **Error handling** — standard JSON-RPC error codes (-32700, -32600, -32601, -32602, -32603)

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
