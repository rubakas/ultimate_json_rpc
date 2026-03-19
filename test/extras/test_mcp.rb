# frozen_string_literal: true

require "test_helper"
require "reclamo/extras/mcp"
require "json"

# Helper used by all MCP test classes
module MCPTestHelper
  private

  def mcp_call(mcp, method, params = nil)
    mcp_server = mcp.instance_variable_get(:@mcp_server)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(mcp_server.handle(JSON.generate(request)))["result"]
  end

  def mcp_notify(mcp, method)
    mcp_server = mcp.instance_variable_get(:@mcp_server)
    request = { "jsonrpc" => "2.0", "method" => method }
    mcp_server.handle(JSON.generate(request))
  end
end

class TestMCPInitialize < Minitest::Test
  include MCPTestHelper

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
    Reclamo::Extras::MCP.new(server)
  end
end

class TestMCPToolsList < Minitest::Test
  include MCPTestHelper

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
    mcp = Reclamo::Extras::MCP.new(server)
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
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    tool = result["tools"].find { |t| t["name"] == "double" }

    assert_equal "number", tool["inputSchema"]["properties"]["n"]["type"]
  end

  def test_tool_with_keyword_params
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    greet_tool = result["tools"].find { |t| t["name"] == "greet" }

    assert_includes greet_tool["inputSchema"]["required"], "name"
  end

  def test_zero_param_tool_has_input_schema
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    ping_tool = result["tools"].find { |t| t["name"] == "ping" }

    assert_equal({ "type" => "object" }, ping_tool["inputSchema"])
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
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/list")
    names = result["tools"].map { |t| t["name"] }

    assert_includes names, "math.add"
  end

  private

  def build_mcp
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Extras::MCP.new(server)
  end
end

class TestMCPToolsCall < Minitest::Test
  include MCPTestHelper

  def test_call_positional_method
    mcp = build_mcp
    result = mcp_call(mcp, "tools/call", { "name" => "add", "arguments" => { "left" => 2, "right" => 3 } })

    assert_equal [{ "type" => "text", "text" => "5" }], result["content"]
  end

  def test_call_keyword_method
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "greet", "arguments" => { "name" => "Alice" } })

    assert_equal "Hi, Alice!", result["content"][0]["text"]
  end

  def test_call_returns_string_result
    server = Reclamo::Server.new
    server.expose_method("hello") { "world" }
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "hello" })

    assert_equal "world", result["content"][0]["text"]
  end

  def test_call_returns_complex_result_as_json
    server = Reclamo::Server.new
    server.expose_method("info") { { "status" => "ok", "count" => 42 } }
    mcp = Reclamo::Extras::MCP.new(server)
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

  def test_call_nonexistent_method_with_arguments_returns_error
    mcp = build_mcp
    result = mcp_call(mcp, "tools/call", { "name" => "nonexistent", "arguments" => { "x" => 1 } })

    assert_equal true, result["isError"]
  end

  def test_call_with_empty_arguments
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "ping" })

    assert_equal "pong", result["content"][0]["text"]
  end

  def test_call_goes_through_middleware
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false
    server.use { |_req, nxt| called = true; nxt.call } # rubocop:disable Style/Semicolon
    mcp = Reclamo::Extras::MCP.new(server)
    mcp_call(mcp, "tools/call", { "name" => "add", "arguments" => { "left" => 1, "right" => 2 } })

    assert called
  end

  def test_call_method_returning_nil
    server = Reclamo::Server.new
    server.expose_method("void") { nil }
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "void" })

    assert_equal "null", result["content"][0]["text"]
    refute result.key?("isError")
  end

  def test_call_with_nil_positional_argument
    server = Reclamo::Server.new
    server.expose_method("identity", &:inspect)
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "identity", "arguments" => { "arg" => nil } })

    assert_equal "nil", result["content"][0]["text"]
  end

  def test_call_missing_required_positional_argument
    mcp = build_mcp
    result = mcp_call(mcp, "tools/call", { "name" => "add", "arguments" => { "left" => 2 } })

    assert_equal true, result["isError"]
  end

  def test_call_with_namespaced_method
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math")
    mcp = Reclamo::Extras::MCP.new(server)
    result = mcp_call(mcp, "tools/call", { "name" => "math.add", "arguments" => { "left" => 5, "right" => 3 } })

    assert_equal "8", result["content"][0]["text"]
  end

  private

  def build_mcp
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Extras::MCP.new(server)
  end
end

class TestMCPUniqueCallIds < Minitest::Test
  include MCPTestHelper

  def test_sequential_tool_calls_produce_different_ids
    server = Reclamo::Server.new
    server.expose(Calculator)
    mcp = Reclamo::Extras::MCP.new(server)
    mcp_server = mcp.instance_variable_get(:@mcp_server)

    ids = 2.times.map do
      request = { "jsonrpc" => "2.0", "method" => "tools/call",
                  "params" => { "name" => "add", "arguments" => { "left" => 1, "right" => 2 } }, "id" => 1 }
      mcp_server.handle(JSON.generate(request))
      mcp.instance_variable_get(:@call_id)
    end

    assert_equal 2, ids.uniq.size, "Expected sequential tool calls to produce different IDs"
  end
end

class TestMCPFreezes < Minitest::Test
  include MCPTestHelper

  def test_freezes_server_on_init
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Extras::MCP.new(server)

    assert_predicate server, :frozen?
  end
end

class TestMCPLifecycle < Minitest::Test
  include MCPTestHelper

  def test_running_returns_false_before_run
    server = Reclamo::Server.new
    server.expose(Calculator)
    mcp = Reclamo::Extras::MCP.new(server)

    refute mcp.running?
  end

  def test_stop_before_run_does_not_raise
    server = Reclamo::Server.new
    server.expose(Calculator)
    mcp = Reclamo::Extras::MCP.new(server)

    assert_nil mcp.stop
  end
end

class TestMCPNotifications < Minitest::Test
  include MCPTestHelper

  def test_initialized_notification
    server = Reclamo::Server.new
    server.expose(Calculator)
    mcp = Reclamo::Extras::MCP.new(server)

    assert_nil mcp_notify(mcp, "notifications/initialized")
  end
end
