# frozen_string_literal: true

require "test_helper"
require "reclamo/mcp"
require "json"

class TestMCPInitialize < Minitest::Test
  def test_initialize_returns_protocol_version
    result = mcp_call(build_mcp, "initialize")

    assert_equal "2024-11-05", result["protocolVersion"]
  end

  def test_initialize_returns_tools_capability
    result = mcp_call(build_mcp, "initialize")

    assert result["capabilities"].key?("tools")
  end

  def test_initialize_returns_server_info
    result = mcp_call(build_mcp(name: "Test API", version: "2.0"), "initialize")

    assert_equal "Test API", result["serverInfo"]["name"]
    assert_equal "2.0", result["serverInfo"]["version"]
  end

  def test_initialize_defaults_server_info
    result = mcp_call(build_mcp, "initialize")

    assert_equal "Reclamo MCP Server", result["serverInfo"]["name"]
    assert_equal "0.0.0", result["serverInfo"]["version"]
  end

  private

  def build_mcp(name: nil, version: nil)
    server = Reclamo::Server.new(name:, version:)
    server.expose(Calculator)
    Reclamo::MCP.new(server)
  end
end

class TestMCPToolsList < Minitest::Test
  def test_tools_list_returns_methods
    mcp = build_mcp
    result = mcp_call(mcp, "tools/list")
    names = result["tools"].map { |t| t["name"] }

    assert_includes names, "add"
    assert_includes names, "divide"
  end

  def test_tool_has_name_and_input_schema
    mcp = build_mcp
    result = mcp_call(mcp, "tools/list")
    add_tool = result["tools"].find { |t| t["name"] == "add" }

    assert_equal "add", add_tool["name"]
    assert_equal "object", add_tool["inputSchema"]["type"]
  end

  def test_tool_includes_description
    server = Reclamo::Server.new
    server.expose_method("ping", description: "Health check") { "pong" }
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    ping_tool = result["tools"].find { |t| t["name"] == "ping" }

    assert_equal "Health check", ping_tool["description"]
  end

  def test_tool_schema_includes_required_params
    mcp = build_mcp
    result = mcp_call(mcp, "tools/list")
    add_tool = result["tools"].find { |t| t["name"] == "add" }

    assert_includes add_tool["inputSchema"]["required"], "left"
    assert_includes add_tool["inputSchema"]["required"], "right"
  end

  def test_tool_schema_includes_param_types
    server = Reclamo::Server.new
    server.expose_method("double", params_schema: { n: { "type" => "number" } }) { |n| n * 2 }
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    tool = result["tools"].find { |t| t["name"] == "double" }

    assert_equal "number", tool["inputSchema"]["properties"]["n"]["type"]
  end

  def test_tool_with_keyword_params
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    greet_tool = result["tools"].find { |t| t["name"] == "greet" }

    assert_includes greet_tool["inputSchema"]["required"], "name"
  end

  def test_mcp_methods_not_in_tools_list
    mcp = build_mcp
    result = mcp_call(mcp, "tools/list")
    names = result["tools"].map { |t| t["name"] }

    refute_includes names, "initialize"
    refute_includes names, "tools/list"
    refute_includes names, "tools/call"
  end

  def test_namespaced_tools
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math")
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    names = result["tools"].map { |t| t["name"] }

    assert_includes names, "math.add"
  end

  private

  def build_mcp
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::MCP.new(server)
  end
end

class TestMCPToolsCall < Minitest::Test
  def test_call_positional_method
    mcp = build_mcp
    result = mcp_call(mcp, "tools/call", { "name" => "add", "arguments" => { "left" => 2, "right" => 3 } })

    assert_equal [{ "type" => "text", "text" => "5" }], result["content"]
  end

  def test_call_keyword_method
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "greet", "arguments" => { "name" => "Alice" } })

    assert_equal "Hi, Alice!", result["content"][0]["text"]
  end

  def test_call_returns_string_result
    server = Reclamo::Server.new
    server.expose_method("hello") { "world" }
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "hello" })

    assert_equal "world", result["content"][0]["text"]
  end

  def test_call_returns_complex_result_as_json
    server = Reclamo::Server.new
    server.expose_method("info") { { "status" => "ok", "count" => 42 } }
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "info" })
    parsed = JSON.parse(result["content"][0]["text"])

    assert_equal "ok", parsed["status"]
    assert_equal 42, parsed["count"]
  end

  def test_call_nonexistent_method_returns_error
    mcp = build_mcp
    result = mcp_call(mcp, "tools/call", { "name" => "nonexistent" })

    assert_equal true, result["isError"]
    assert_match(/not found/i, result["content"][0]["text"])
  end

  def test_call_with_empty_arguments
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "ping" })

    assert_equal "pong", result["content"][0]["text"]
  end

  def test_call_goes_through_middleware
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false
    server.use { |_req, nxt| called = true; nxt.call } # rubocop:disable Style/Semicolon
    mcp = Reclamo::MCP.new(server)
    mcp_call(mcp, "tools/call", { "name" => "add", "arguments" => { "left" => 1, "right" => 2 } })

    assert called
  end

  def test_call_with_namespaced_method
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math")
    mcp = Reclamo::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "math.add", "arguments" => { "left" => 5, "right" => 3 } })

    assert_equal "8", result["content"][0]["text"]
  end

  private

  def build_mcp
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::MCP.new(server)
  end
end

class TestMCPNotifications < Minitest::Test
  def test_initialized_notification
    mcp = build_mcp
    # notifications/initialized is a no-op notification (no id)
    response = mcp_handle(mcp, { "jsonrpc" => "2.0", "method" => "notifications/initialized" })

    assert_nil response
  end

  private

  def build_mcp
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::MCP.new(server)
  end

  def mcp_handle(mcp, request)
    mcp_server = mcp.instance_variable_get(:@mcp_server)
    mcp_server.handle(JSON.generate(request))
  end
end

# Helper used by all MCP test classes
module MCPTestHelper
  private

  def mcp_call(mcp, method, params = nil)
    mcp_server = mcp.instance_variable_get(:@mcp_server)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(mcp_server.handle(JSON.generate(request)))["result"]
  end
end

# Include the helper in all MCP test classes
[TestMCPInitialize, TestMCPToolsList, TestMCPToolsCall].each { |klass| klass.include(MCPTestHelper) }
