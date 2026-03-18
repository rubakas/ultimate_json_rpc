#!/usr/bin/env ruby
# frozen_string_literal: true

# Error handling patterns
#
# Run: ruby examples/error_handling.rb

require "reclamo"
require "reclamo/logging"
require "json"
require "logger"

module BankService
  def self.transfer(from:, to:, amount:)
    raise Reclamo::ApplicationError.new(code: 1001, message: "Insufficient funds", data: { balance: 50 }) if amount > 100
    raise Reclamo::ApplicationError.new(code: 1002, message: "Account frozen") if from == "frozen"

    { from:, to:, amount:, status: "completed" }
  end
end

server = Reclamo::Server.new(name: "Bank API", version: "1.0", expose_errors: true)
server.expose(BankService, descriptions: { transfer: "Transfer money between accounts" })
server.register_error(code: 1001, message: "InsufficientFunds", description: "Account balance too low for transfer")
server.register_error(code: 1002, message: "AccountFrozen", description: "Account is frozen and cannot transact")
server.log_to(Logger.new($stdout, level: :info))

# Successful transfer
puts "=== Successful transfer ==="
puts server.handle(JSON.generate({
  "jsonrpc" => "2.0", "method" => "transfer",
  "params" => { "from" => "alice", "to" => "bob", "amount" => 50 }, "id" => 1
}))

# Application error — insufficient funds
puts "\n=== Insufficient funds ==="
puts server.handle(JSON.generate({
  "jsonrpc" => "2.0", "method" => "transfer",
  "params" => { "from" => "alice", "to" => "bob", "amount" => 200 }, "id" => 2
}))

# Application error — frozen account
puts "\n=== Frozen account ==="
puts server.handle(JSON.generate({
  "jsonrpc" => "2.0", "method" => "transfer",
  "params" => { "from" => "frozen", "to" => "bob", "amount" => 10 }, "id" => 3
}))

# Method not found
puts "\n=== Method not found ==="
puts server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "withdraw", "id" => 4 }))
