#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-namespace composition and API versioning
#
# Run: ruby examples/multi_namespace.rb

require "ultimate_json_rpc"
require "json"

module Auth
  def self.login(username:, password:) = { token: "tok_#{username}", expires: 3600 }
  def self.logout(token:) = { revoked: true }
end

module Users
  def self.list = [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }]
  def self.get(id:) = { id:, name: id == 1 ? "Alice" : "Bob" }
end

# Compose multiple objects into a single endpoint
server = UltimateJsonRpc::Server.new(name: "My API", version: "1.0")
server.expose(Auth, namespace: "auth", descriptions: { login: "Authenticate user", logout: "Revoke token" })
server.expose(Users, namespace: "users", descriptions: { list: "List all users", get: "Get user by ID" })

# API versioning via namespaces
module CalcV1
  def self.add(a, b) = a + b
end

module CalcV2
  def self.add(a, b) = { result: a + b, version: 2 }
end

server.expose(CalcV1, namespace: "v1.calc")
server.expose(CalcV2, namespace: "v2.calc")

# Test it
puts "Methods: #{server.methods_list.join(", ")}"
puts

[
  { "jsonrpc" => "2.0", "method" => "auth.login", "params" => { "username" => "alice", "password" => "secret" }, "id" => 1 },
  { "jsonrpc" => "2.0", "method" => "users.list", "id" => 2 },
  { "jsonrpc" => "2.0", "method" => "v1.calc.add", "params" => [2, 3], "id" => 3 },
  { "jsonrpc" => "2.0", "method" => "v2.calc.add", "params" => [2, 3], "id" => 4 }
].each do |req|
  puts "#{req["method"]} => #{server.handle(JSON.generate(req))}"
end
