# frozen_string_literal: true

require "test_helper"
require "json"

class TestServerDiscover < Minitest::Test
  def test_rpc_discover_returns_method_names
    methods = discover_methods_for(Calculator)

    assert_equal "add", methods.find { |m| m["name"] == "add" }["name"]
  end

  def test_rpc_discover_includes_param_info
    methods = discover_methods_for(Calculator)
    add_method = methods.find { |m| m["name"] == "add" }

    assert_equal 2, add_method["params"].size
    assert_equal true, add_method["params"][0]["required"]
  end

  def test_rpc_discover_includes_custom_methods
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    method_names = discover(server).map { |m| m["name"] }

    assert_includes method_names, "ping"
  end

  def test_rpc_discover_keyword_params_required
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"), namespace: "greeter")
    greet_method = discover(server).find { |m| m["name"] == "greeter.greet" }
    name_param = greet_method["params"][0]

    assert_equal true, name_param["required"]
    assert_equal true, name_param["keyword"]
  end

  def test_rpc_discover_no_params_omits_key
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    ping_method = discover(server).find { |m| m["name"] == "ping" }

    refute ping_method.key?("params")
  end

  def test_rpc_discover_variadic_params
    server = Reclamo::Server.new
    server.expose_method("sum") { |*nums| nums.sum }
    sum_method = discover(server).find { |m| m["name"] == "sum" }

    assert_equal true, sum_method["params"][0]["variadic"]
  end

  def test_rpc_discover_as_notification
    server = Reclamo::Server.new
    server.expose(Calculator)

    assert_nil server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "rpc.discover" }))
  end

  def test_rpc_discover_not_in_methods_list
    server = Reclamo::Server.new
    server.expose(Calculator)

    refute_includes server.methods_list, "rpc.discover"
  end

  def test_rpc_discover_callable_methods
    server = Reclamo::Server.new
    server.expose_method("double", ->(n) { n * 2 })
    methods = discover(server)
    double_method = methods.find { |m| m["name"] == "double" }

    assert double_method
    assert_equal 1, double_method["params"].size
  end

  private

  def discover_methods_for(target)
    server = Reclamo::Server.new
    server.expose(target)
    discover(server)
  end

  def discover(server)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))["result"]["methods"]
  end
end

module DiscoverHelper
  private

  def discover_result(server)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))["result"]
  end

  def discover_methods(server)
    discover_result(server)["methods"]
  end
end

class TestServerDiscoverDescriptions < Minitest::Test
  include DiscoverHelper

  def test_expose_method_description
    server = Reclamo::Server.new
    server.expose_method("ping", description: "Health check") { "pong" }

    assert_equal "Health check", discover_methods(server).find { |m| m["name"] == "ping" }["description"]
  end

  def test_expose_descriptions
    server = Reclamo::Server.new
    server.expose(Calculator, descriptions: { add: "Add two numbers", divide: "Divide two numbers" })
    methods = discover_methods(server)

    assert_equal "Add two numbers", methods.find { |m| m["name"] == "add" }["description"]
    assert_equal "Divide two numbers", methods.find { |m| m["name"] == "divide" }["description"]
  end

  def test_omits_description_when_not_provided
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_methods(server).find { |m| m["name"] == "ping" }.key?("description")
  end

  def test_descriptions_with_string_keys
    server = Reclamo::Server.new
    server.expose(Calculator, descriptions: { "add" => "Sum values" })

    assert_equal "Sum values", discover_methods(server).find { |m| m["name"] == "add" }["description"]
  end

  def test_descriptions_with_namespace
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math", descriptions: { add: "Sum", divide: "Quotient" })
    methods = discover_methods(server)

    assert_equal "Sum", methods.find { |m| m["name"] == "math.add" }["description"]
    assert_equal "Quotient", methods.find { |m| m["name"] == "math.divide" }["description"]
  end
end

class TestServerDiscoverServiceInfo < Minitest::Test
  include DiscoverHelper

  def test_includes_name_and_version
    server = Reclamo::Server.new(name: "Calculator API", version: "1.0.0")
    server.expose(Calculator)
    result = discover_result(server)

    assert_equal "Calculator API", result["name"]
    assert_equal "1.0.0", result["version"]
  end

  def test_omits_name_and_version_when_not_set
    server = Reclamo::Server.new
    server.expose(Calculator)
    result = discover_result(server)

    refute result.key?("name")
    refute result.key?("version")
  end

  def test_name_and_version_readers
    server = Reclamo::Server.new(name: "My API", version: "2.0")

    assert_equal "My API", server.name
    assert_equal "2.0", server.version
  end

  def test_name_and_version_default_to_nil
    server = Reclamo::Server.new

    assert_nil server.name
    assert_nil server.version
  end

  def test_includes_description
    server = Reclamo::Server.new(name: "API", description: "A test API server")
    server.expose(Calculator)
    result = discover_result(server)

    assert_equal "A test API server", result["description"]
  end

  def test_omits_description_when_not_set
    server = Reclamo::Server.new(name: "API")
    server.expose(Calculator)
    result = discover_result(server)

    refute result.key?("description")
  end

  def test_description_reader
    server = Reclamo::Server.new(description: "My service")

    assert_equal "My service", server.description
  end

  def test_description_defaults_to_nil
    server = Reclamo::Server.new

    assert_nil server.description
  end

  def test_frozen_server_discover_works
    server = Reclamo::Server.new(name: "Frozen API", version: "1.0")
    server.expose(Calculator)
    server.freeze
    result = discover_result(server)

    assert_equal "Frozen API", result["name"]
    assert_includes result["methods"].map { |m| m["name"] }, "add"
  end
end
