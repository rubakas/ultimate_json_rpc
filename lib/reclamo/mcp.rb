# frozen_string_literal: true

require_relative "stdio"

module Reclamo
  class MCP
    PROTOCOL_VERSION = "2024-11-05"

    def initialize(server, input: $stdin, output: $stdout)
      @app_server = server
      @mcp_server = build_mcp_server
      @input = input
      @output = output
    end

    def run
      Stdio.new(@mcp_server, input: @input, output: @output).run
    end

    private

    def build_mcp_server
      mcp = Server.new(name: @app_server.name, version: @app_server.version)
      mcp.expose_method("initialize") { mcp_initialize }
      mcp.expose_method("notifications/initialized") { nil }
      mcp.expose_method("tools/list") { mcp_tools_list }
      mcp.expose_method("tools/call") { |name:, arguments: {}| mcp_tools_call(name, arguments) }
      mcp
    end

    def mcp_initialize
      {
        "protocolVersion" => PROTOCOL_VERSION,
        "capabilities" => { "tools" => {} },
        "serverInfo" => {
          "name" => @app_server.name || "Reclamo MCP Server",
          "version" => @app_server.version || "0.0.0"
        }
      }
    end

    def mcp_tools_list
      { "tools" => @app_server.methods_info.map { |m| to_mcp_tool(m) } }
    end

    def mcp_tools_call(name, arguments)
      request = build_call_request(name, arguments)
      response = JSON.parse(@app_server.handle_parsed(request))
      format_call_response(response)
    end

    def to_mcp_tool(method_info)
      tool = { "name" => method_info["name"] }
      tool["description"] = method_info["description"] if method_info["description"]
      tool["inputSchema"] = build_input_schema(method_info["params"]) if method_info["params"]
      tool
    end

    def build_input_schema(params)
      schema = { "type" => "object" }
      properties = {}
      required = []

      params.each do |p|
        next if p["variadic"]

        properties[p["name"]] = p.fetch("schema", {})
        required << p["name"] if p["required"]
      end

      schema["properties"] = properties unless properties.empty?
      schema["required"] = required unless required.empty?
      schema
    end

    def build_call_request(name, arguments)
      request = { "jsonrpc" => "2.0", "method" => name, "id" => "mcp" }
      return request if arguments.nil? || arguments.empty?

      method_info = @app_server.methods_info.find { |m| m["name"] == name }
      request["params"] = convert_arguments(arguments, method_info)
      request
    end

    def convert_arguments(arguments, method_info)
      params = method_info&.dig("params")
      return arguments unless params

      # Keyword params: pass as Hash (Reclamo converts to **kwargs)
      return arguments if params.any? { |p| p["keyword"] }

      # Positional params: convert Hash to Array in parameter order
      params.filter_map { |p| arguments[p["name"]] unless p["variadic"] }
    end

    def format_call_response(response)
      if response&.key?("error")
        { "content" => [{ "type" => "text", "text" => response.dig("error", "message") }], "isError" => true }
      else
        result = response&.fetch("result", nil)
        text = result.is_a?(String) ? result : JSON.generate(result)
        { "content" => [{ "type" => "text", "text" => text }] }
      end
    end
  end
end
