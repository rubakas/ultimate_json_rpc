#!/usr/bin/env ruby
# frozen_string_literal: true

# Testing patterns with Reclamo
#
# Run: ruby examples/testing_patterns.rb

require "reclamo"
require "reclamo/extras/test_helpers"
require "reclamo/extras/mock_server"
require "reclamo/extras/recorder"
require "reclamo/extras/profiler"
require "json"

# === 1. Test Helpers ===
puts "=== Test Helpers ==="

module Calculator
  def self.add(a, b) = a + b
end

server = Reclamo::Server.new
server.expose(Calculator)

include Reclamo::Extras::TestHelpers # rubocop:disable Style/MixinUsage

response = rpc_call(server, "add", params: [2, 3])
puts "rpc_call result: #{response["result"]}"

error_response = rpc_call(server, "nonexistent")
puts "rpc_call error: #{error_response["error"]["code"]}"

# === 2. Mock Server ===
puts "\n=== Mock Server ==="

mock = Reclamo::Extras::MockServer.new
mock.stub("users.list", params: nil, result: [{ "id" => 1, "name" => "Alice" }])
mock.stub("users.get", params: { "id" => 1 }, result: { "id" => 1, "name" => "Alice" })
mock.stub_any("health", "ok")

puts "Mock list: #{mock.handle('{"jsonrpc":"2.0","method":"users.list","id":1}')}"
puts "Mock get:  #{mock.handle('{"jsonrpc":"2.0","method":"users.get","params":{"id":1},"id":2}')}"

# === 3. Recorder ===
puts "\n=== Recorder ==="

recorder = Reclamo::Extras::Recorder.new(server)
server.handle('{"jsonrpc":"2.0","method":"add","params":[10,20],"id":1}')
server.handle('{"jsonrpc":"2.0","method":"add","params":[5,5],"id":2}')

puts "Recorded #{recorder.size} exchanges:"
recorder.exchanges.each { |e| puts "  #{e["method"]}(#{e["params"]}) => #{e["result"]} (#{e["duration"]}s)" }

# === 4. Profiler ===
puts "\n=== Profiler ==="

profiler = Reclamo::Extras::Profiler.new(server)
50.times { |i| server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i })) }

stats = profiler["add"]
puts "add: #{stats[:count]} calls, avg=#{stats[:avg]}s, p99=#{stats[:p99]}s"
