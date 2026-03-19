# frozen_string_literal: true

require_relative "stdio"

module Reclamo
  class MCP
    PROTOCOL_VERSION = "2024-11-05"

    def initialize(server, input: $stdin, output: $stdout, json: JSON)
      @app_server = server
      @app_server.freeze
      @json = json
      @methods_cache = server.methods_info
      @methods_index = @methods_cache.to_h { |m| [m["name"], m] }
      @mcp_server = build_mcp_server
      @input = input
      @output = output
      @stdio = nil
    end

    def run
      @stdio = Stdio.new(@mcp_server, input: @input, output: @output)
      @stdio.run
    end

    def stop
      @stdio&.stop
    end

    def running?
      @stdio&.running? || false
    end

    private

    def build_mcp_server
      mcp = Server.new(name: @app_server.name, version: @app_server.version, json: @json)
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
      { "tools" => @methods_cache.map { |m| to_mcp_tool(m) } }
    end

    def mcp_tools_call(name, arguments)
      request = build_call_request(name, arguments)
      raw = @app_server.handle_parsed(request)
      return { "content" => [{ "type" => "text", "text" => "No response from server" }], "isError" => true } unless raw

      response = @json.parse(raw)
      format_call_response(response)
    rescue StandardError => e
      { "content" => [{ "type" => "text", "text" => e.message }], "isError" => true }
    end

    def to_mcp_tool(method_info)
      tool = { "name" => method_info["name"] }
      tool["description"] = method_info["description"] if method_info["description"]
      tool["inputSchema"] = method_info["params"] ? build_input_schema(method_info["params"]) : { "type" => "object" }
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

      method_info = @methods_index[name]
      request["params"] = convert_arguments(arguments, method_info)
      request
    end

    def convert_arguments(arguments, method_info)
      params = method_info&.dig("params")
      return arguments unless params

      arguments = arguments.transform_keys(&:to_s)
      return arguments if params.any? { |p| p["keyword"] }

      convert_to_positional(arguments, params)
    end

    def convert_to_positional(arguments, params)
      params.reject { |p| p["variadic"] }.map do |p|
        validate_required_argument!(arguments, p)
        arguments[p["name"]]
      end
    end

    def validate_required_argument!(arguments, param)
      name = param["name"]
      return if name.empty? || !param["required"] || arguments.key?(name)

      raise ArgumentError, "missing required argument: #{name}"
    end

    def format_call_response(response)
      if response&.key?("error")
        { "content" => [{ "type" => "text", "text" => response.dig("error", "message").to_s }], "isError" => true }
      else
        result = response&.fetch("result", nil)
        text = result.is_a?(String) ? result : @json.generate(result)
        { "content" => [{ "type" => "text", "text" => text }] }
      end
    end
  end
end
