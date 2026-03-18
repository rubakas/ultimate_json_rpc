#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP server exposing Ruby methods as AI tools
#
# Run:  ruby examples/mcp_server.rb
# Use:  Configure as an MCP server in Claude Desktop, Cursor, etc.
#
# claude_desktop_config.json:
#   {
#     "mcpServers": {
#       "calculator": {
#         "command": "ruby",
#         "args": ["examples/mcp_server.rb"]
#       }
#     }
#   }

require "reclamo"
require "reclamo/mcp"

module MathTools
  def self.add(a, b) = a + b
  def self.subtract(a, b) = a - b
  def self.multiply(a, b) = a * b
  def self.divide(a, b)
    raise ArgumentError, "Division by zero" if b.zero?

    a.to_f / b
  end
end

server = Reclamo::Server.new(name: "Math Tools", version: "1.0")
server.expose(MathTools,
              descriptions: { add: "Add two numbers", subtract: "Subtract b from a",
                              multiply: "Multiply two numbers", divide: "Divide a by b" },
              params_schema: { add: { a: { "type" => "number" }, b: { "type" => "number" } },
                               subtract: { a: { "type" => "number" }, b: { "type" => "number" } },
                               multiply: { a: { "type" => "number" }, b: { "type" => "number" } },
                               divide: { a: { "type" => "number" }, b: { "type" => "number" } } })

Reclamo::MCP.new(server).run
