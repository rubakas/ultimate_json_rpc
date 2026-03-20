# frozen_string_literal: true

require "test_helper"
require "json"
require "support/discover_helper"

class TestServerDiscover < Minitest::Test
  def test_rpc_discover_returns_method_names
    methods = discover_methods_for(Calculator)

    refute_nil(methods.find { |m| m["name"] == "add" })
  end

  def test_rpc_discover_includes_param_info
    methods = discover_methods_for(Calculator)
    add_method = methods.find { |m| m["name"] == "add" }

    assert_equal 2, add_method["params"].size
    assert add_method["params"][0]["required"]
  end

  def test_rpc_discover_includes_custom_methods
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    method_names = discover(server).map { |m| m["name"] }

    assert_includes method_names, "ping"
  end

  def test_rpc_discover_keyword_params_required
    server = UltimateJsonRpc::Server.new
    server.expose(Greeter.new("Hi"), namespace: "greeter")
    greet_method = discover(server).find { |m| m["name"] == "greeter.greet" }
    name_param = greet_method["params"][0]

    assert name_param["required"]
    assert name_param["keyword"]
  end

  def test_rpc_discover_no_params_omits_key
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    ping_method = discover(server).find { |m| m["name"] == "ping" }

    refute ping_method.key?("params")
  end

  def test_rpc_discover_variadic_params
    server = UltimateJsonRpc::Server.new
    server.expose_method("sum") { |*nums| nums.sum }
    sum_method = discover(server).find { |m| m["name"] == "sum" }

    assert sum_method["params"][0]["variadic"]
  end

  def test_rpc_discover_as_notification
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    assert_nil server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "rpc.discover" }))
  end

  def test_rpc_discover_not_in_methods_list
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    refute_includes server.methods_list, "rpc.discover"
  end

  def test_rpc_discover_callable_methods
    server = UltimateJsonRpc::Server.new
    server.expose_method("double", ->(n) { n * 2 })
    methods = discover(server)
    double_method = methods.find { |m| m["name"] == "double" }

    assert double_method
    assert_equal 1, double_method["params"].size
  end

  def test_rpc_discover_on_empty_server
    server = UltimateJsonRpc::Server.new
    methods = discover(server)

    assert_empty methods
  end

  def test_rpc_discover_response_has_no_error_key
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert response.key?("result")
    refute response.key?("error")
  end

  private

  def discover_methods_for(target)
    server = UltimateJsonRpc::Server.new
    server.expose(target)
    discover(server)
  end

  def discover(server)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))["result"]["methods"]
  end
end

class TestServerDiscoverOpenRPC < Minitest::Test
  include DiscoverHelper

  def test_includes_openrpc_version
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    assert_equal "1.3.2", discover_result(server)["openrpc"]
  end

  def test_info_object_structure
    server = UltimateJsonRpc::Server.new(name: "My API", version: "2.0", description: "A JSON-RPC server")
    server.expose(Calculator)
    info = discover_result(server)["info"]

    assert_equal "My API", info["title"]
    assert_equal "2.0", info["version"]
    assert_equal "A JSON-RPC server", info["description"]
  end

  def test_methods_array_present
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    result = discover_result(server)

    assert_kind_of Array, result["methods"]
    refute_empty result["methods"]
  end

  def test_full_document_structure
    server = UltimateJsonRpc::Server.new(name: "Test", version: "1.0")
    server.expose_method("add", description: "Sum", returns: { "type" => "number" }) { |a, b| a + b }
    result = discover_result(server)

    assert_equal "1.3.2", result["openrpc"]
    assert_equal "Test", result["info"]["title"]
    method = result["methods"].first

    assert_equal "add", method["name"]
    assert_equal "Sum", method["description"]
    assert_equal "number", method["result"]["type"]
  end
end

class TestServerDiscoverDescriptions < Minitest::Test
  include DiscoverHelper

  def test_expose_method_description
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping", description: "Health check") { "pong" }

    assert_equal "Health check", discover_methods(server).find { |m| m["name"] == "ping" }["description"]
  end

  def test_expose_descriptions
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, descriptions: { add: "Add two numbers", divide: "Divide two numbers" })
    methods = discover_methods(server)

    assert_equal "Add two numbers", methods.find { |m| m["name"] == "add" }["description"]
    assert_equal "Divide two numbers", methods.find { |m| m["name"] == "divide" }["description"]
  end

  def test_omits_description_when_not_provided
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_methods(server).find { |m| m["name"] == "ping" }.key?("description")
  end

  def test_expose_method_lambda_with_description
    server = UltimateJsonRpc::Server.new
    server.expose_method("double", ->(n) { n * 2 }, description: "Double a number")
    method_info = discover_methods(server).find { |m| m["name"] == "double" }

    assert_equal "Double a number", method_info["description"]
    assert_equal 1, method_info["params"].size
  end

  def test_descriptions_with_string_keys
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, descriptions: { "add" => "Sum values" })

    assert_equal "Sum values", discover_methods(server).find { |m| m["name"] == "add" }["description"]
  end

  def test_descriptions_with_namespace
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, namespace: "math", descriptions: { add: "Sum", divide: "Quotient" })
    methods = discover_methods(server)

    assert_equal "Sum", methods.find { |m| m["name"] == "math.add" }["description"]
    assert_equal "Quotient", methods.find { |m| m["name"] == "math.divide" }["description"]
  end
end

class TestServerDiscoverReturns < Minitest::Test
  include DiscoverHelper

  def test_expose_method_with_returns
    server = UltimateJsonRpc::Server.new
    server.expose_method("add", returns: { "type" => "number" }) { |a, b| a + b }
    result = discover_methods(server).find { |m| m["name"] == "add" }["result"]

    assert_equal "result", result["name"]
    assert_equal "number", result["type"]
  end

  def test_expose_with_returns_hash
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, returns: { add: { "type" => "number" }, divide: { "type" => "number" } })
    methods = discover_methods(server)

    assert_equal "number", methods.find { |m| m["name"] == "add" }["result"]["type"]
    assert_equal "number", methods.find { |m| m["name"] == "divide" }["result"]["type"]
  end

  def test_expose_with_returns_string_keys
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, returns: { "add" => { "type" => "integer" } })

    assert_equal "integer", discover_methods(server).find { |m| m["name"] == "add" }["result"]["type"]
  end

  def test_expose_with_returns_and_namespace
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, namespace: "math", returns: { add: { "type" => "number" } })
    result = discover_methods(server).find { |m| m["name"] == "math.add" }["result"]

    assert_equal "number", result["type"]
  end

  def test_omits_result_when_not_provided
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_methods(server).find { |m| m["name"] == "ping" }.key?("result")
  end

  def test_returns_with_description
    server = UltimateJsonRpc::Server.new
    server.expose_method("add", description: "Sum", returns: { "type" => "number" }) { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "add" }

    assert_equal "Sum", method_info["description"]
    assert_equal "number", method_info["result"]["type"]
  end

  def test_returns_with_callable
    server = UltimateJsonRpc::Server.new
    server.expose_method("double", ->(n) { n * 2 }, returns: { "type" => "number" })

    assert_equal "number", discover_methods(server).find { |m| m["name"] == "double" }["result"]["type"]
  end

  def test_returns_survives_freeze
    server = UltimateJsonRpc::Server.new
    server.expose_method("add", returns: { "type" => "number" }) { |a, b| a + b }
    server.freeze

    assert_equal "number", discover_methods(server).find { |m| m["name"] == "add" }["result"]["type"]
  end

  def test_returns_string_value_wrapped_in_schema
    server = UltimateJsonRpc::Server.new
    server.expose_method("greet", returns: "string") { |name| "Hi #{name}" }
    result = discover_methods(server).find { |m| m["name"] == "greet" }["result"]

    assert_equal "result", result["name"]
    assert_equal({ "type" => "string" }, result["schema"])
  end
end

class TestServerDiscoverServiceInfo < Minitest::Test
  include DiscoverHelper

  def test_includes_name_and_version_in_info
    server = UltimateJsonRpc::Server.new(name: "Calculator API", version: "1.0.0")
    server.expose(Calculator)
    info = discover_result(server)["info"]

    assert_equal "Calculator API", info["title"]
    assert_equal "1.0.0", info["version"]
  end

  def test_omits_info_when_nothing_set
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    result = discover_result(server)

    refute result.key?("info")
  end

  def test_name_and_version_readers
    server = UltimateJsonRpc::Server.new(name: "My API", version: "2.0")

    assert_equal "My API", server.name
    assert_equal "2.0", server.version
  end

  def test_name_and_version_default_to_nil
    server = UltimateJsonRpc::Server.new

    assert_nil server.name
    assert_nil server.version
  end

  def test_includes_description_in_info
    server = UltimateJsonRpc::Server.new(name: "API", description: "A test API server")
    server.expose(Calculator)
    info = discover_result(server)["info"]

    assert_equal "A test API server", info["description"]
  end

  def test_omits_description_when_not_set
    server = UltimateJsonRpc::Server.new(name: "API")
    server.expose(Calculator)
    info = discover_result(server)["info"]

    refute info.key?("description")
  end

  def test_description_reader
    server = UltimateJsonRpc::Server.new(description: "My service")

    assert_equal "My service", server.description
  end

  def test_description_defaults_to_nil
    server = UltimateJsonRpc::Server.new

    assert_nil server.description
  end

  def test_frozen_server_discover_works
    server = UltimateJsonRpc::Server.new(name: "Frozen API", version: "1.0")
    server.expose(Calculator)
    server.freeze
    result = discover_result(server)

    assert_equal "Frozen API", result["info"]["title"]
    assert_includes result["methods"].map { |m| m["name"] }, "add"
  end
end

class TestBuildResultElseBranch < Minitest::Test
  include DiscoverHelper

  def test_returns_non_hash_non_string_wrapped_in_schema
    server = UltimateJsonRpc::Server.new
    server.expose_method("tags", returns: [{ "type" => "string" }]) { %w[a b] }
    method_info = discover_methods(server).find { |m| m["name"] == "tags" }

    assert_equal({ "name" => "result", "schema" => [{ "type" => "string" }] }, method_info["result"])
  end
end

class TestStoreMetadataSymKeyPriority < Minitest::Test
  include DiscoverHelper

  def test_store_metadata_sym_key_takes_priority
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, deprecated: { add: "via sym", "add" => "via str" })
    method_info = discover_methods(server).find { |m| m["name"] == "add" }

    assert_equal "via sym", method_info["deprecated"]
  end
end
