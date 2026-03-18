# frozen_string_literal: true

# Basic Rack/Puma JSON-RPC server
#
# Run:  bundle exec rackup examples/rack_server.ru
# Test: curl -X POST http://localhost:9292 \
#         -H "Content-Type: application/json" \
#         -d '{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'

require "reclamo"
require "reclamo/rack"

module Calculator
  def self.add(a, b) = a + b
  def self.multiply(a, b) = a * b
end

server = Reclamo::Server.new(name: "Calculator API", version: "1.0")
server.expose(Calculator, descriptions: {
  add: "Add two numbers",
  multiply: "Multiply two numbers"
})

run Reclamo::Rack.new(server)
