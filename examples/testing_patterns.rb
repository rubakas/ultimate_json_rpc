#!/usr/bin/env ruby
# frozen_string_literal: true

# Testing patterns with UltimateJsonRpc
#
# Run: ruby examples/testing_patterns.rb

require "ultimate_json_rpc"
require "ultimate_json_rpc/extras/test_helpers"
require "ultimate_json_rpc/extras/recorder"
require "ultimate_json_rpc/extras/profiler"
require "json"

# === 1. Test Helpers ===
puts "=== Test Helpers ==="

module Calculator
  def self.add(a, b) = a + b
end

server = UltimateJsonRpc::Server.new
server.expose(Calculator)

include UltimateJsonRpc::Extras::TestHelpers # rubocop:disable Style/MixinUsage

response = rpc_call(server, "add", params: [2, 3])
puts "rpc_call result: #{response["result"]}"

error_response = rpc_call(server, "nonexistent")
puts "rpc_call error: #{error_response["error"]["code"]}"

# === 2. Recorder ===
puts "\n=== Recorder ==="

recorder = UltimateJsonRpc::Extras::Recorder.new(server)
server.handle('{"jsonrpc":"2.0","method":"add","params":[10,20],"id":1}')
server.handle('{"jsonrpc":"2.0","method":"add","params":[5,5],"id":2}')

puts "Recorded #{recorder.size} exchanges:"
recorder.exchanges.each { |e| puts "  #{e["method"]}(#{e["params"]}) => #{e["result"]} (#{e["duration"]}s)" }

# === 3. Profiler ===
puts "\n=== Profiler ==="

profiler = UltimateJsonRpc::Extras::Profiler.new(server)
50.times { |i| server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i })) }

stats = profiler["add"]
puts "add: #{stats[:count]} calls, avg=#{stats[:avg]}s, p99=#{stats[:p99]}s"
