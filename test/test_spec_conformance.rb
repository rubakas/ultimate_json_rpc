# frozen_string_literal: true

require "test_helper"
require "json"

# JSON-RPC 2.0 Specification Conformance Tests
# Based on examples from https://www.jsonrpc.org/specification
module SpecConformanceSetup
  private

  def build_spec_server
    server = Reclamo::Server.new
    server.expose_method("subtract") do |*args, **kwargs|
      kwargs.any? ? kwargs[:minuend] - kwargs[:subtrahend] : args[0] - args[1]
    end
    server.expose_method("update") { |*args| args }
    server.expose_method("foobar") { "foobar" }
    server.expose_method("sum") { |*args| args.sum }
    server.expose_method("notify_hello") { |_val| nil }
    server.expose_method("get_data") { ["hello", 5] }
    server
  end
end

class TestSpecParams < Minitest::Test
  include SpecConformanceSetup

  def setup
    @server = build_spec_server
  end

  def test_spec_positional_params_subtract
    request = '{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}'
    response = JSON.parse(@server.handle(request))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal 19, response["result"]
    assert_equal 1, response["id"]
  end

  def test_spec_positional_params_reversed
    request = '{"jsonrpc": "2.0", "method": "subtract", "params": [23, 42], "id": 2}'
    response = JSON.parse(@server.handle(request))

    assert_equal(-19, response["result"])
    assert_equal 2, response["id"]
  end

  def test_spec_named_params_subtract
    request = '{"jsonrpc": "2.0", "method": "subtract", "params": {"subtrahend": 23, "minuend": 42}, "id": 3}'
    response = JSON.parse(@server.handle(request))

    assert_equal 19, response["result"]
    assert_equal 3, response["id"]
  end

  def test_spec_named_params_reordered
    request = '{"jsonrpc": "2.0", "method": "subtract", "params": {"minuend": 42, "subtrahend": 23}, "id": 4}'
    response = JSON.parse(@server.handle(request))

    assert_equal 19, response["result"]
    assert_equal 4, response["id"]
  end

  def test_spec_notification
    request = '{"jsonrpc": "2.0", "method": "update", "params": [1,2,3,4,5]}'

    assert_nil @server.handle(request)
  end

  def test_spec_notification_no_params
    request = '{"jsonrpc": "2.0", "method": "foobar"}'

    assert_nil @server.handle(request)
  end

  def test_spec_get_data
    request = '{"jsonrpc": "2.0", "method": "get_data", "id": "1"}'
    response = JSON.parse(@server.handle(request))

    assert_equal ["hello", 5], response["result"]
    assert_equal "1", response["id"]
  end
end

class TestSpecErrors < Minitest::Test
  include SpecConformanceSetup

  def setup
    @server = build_spec_server
  end

  def test_spec_method_not_found
    request = '{"jsonrpc": "2.0", "method": "nonexistent", "id": "1"}'
    response = JSON.parse(@server.handle(request))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_601, response["error"]["code"])
    assert_equal "Method not found", response["error"]["message"]
    assert_equal "1", response["id"]
  end

  def test_spec_parse_error
    request = '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]'
    response = JSON.parse(@server.handle(request))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_700, response["error"]["code"])
    assert_equal "Parse error", response["error"]["message"]
    assert_nil response["id"]
  end

  def test_spec_invalid_request
    request = '{"jsonrpc": "2.0", "method": 1, "params": "bar"}'
    response = JSON.parse(@server.handle(request))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_600, response["error"]["code"])
    assert_equal "Invalid Request", response["error"]["message"]
    assert_nil response["id"]
  end
end

class TestSpecBatch < Minitest::Test
  include SpecConformanceSetup

  def setup
    @server = build_spec_server
  end

  def test_spec_batch_invalid_json
    request = '[{"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},' \
              '{"jsonrpc": "2.0", "method"'
    response = JSON.parse(@server.handle(request))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_spec_empty_batch
    response = JSON.parse(@server.handle("[]"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_spec_invalid_batch_single_element
    responses = JSON.parse(@server.handle("[1]"))

    assert_equal 1, responses.size
    assert_equal(-32_600, responses[0]["error"]["code"])
  end

  def test_spec_invalid_batch_multiple_elements
    responses = JSON.parse(@server.handle("[1,2,3]"))

    assert_equal 3, responses.size
    responses.each { |resp| assert_equal(-32_600, resp["error"]["code"]) }
  end

  def test_spec_batch_mixed_count
    responses = parse_batch_mixed

    assert_equal 5, responses.size
  end

  def test_spec_batch_mixed_sum
    responses = parse_batch_mixed

    assert_equal 7, responses.find { |r| r["id"] == "1" }["result"]
  end

  def test_spec_batch_mixed_subtract
    responses = parse_batch_mixed

    assert_equal 19, responses.find { |r| r["id"] == "2" }["result"]
  end

  def test_spec_batch_mixed_invalid_element
    responses = parse_batch_mixed
    invalid = responses.find { |r| r["error"] && r["id"].nil? }

    assert_equal(-32_600, invalid["error"]["code"])
  end

  def test_spec_batch_mixed_not_found
    responses = parse_batch_mixed

    assert_equal(-32_601, responses.find { |r| r["id"] == "5" }["error"]["code"])
  end

  def test_spec_batch_mixed_foobar
    responses = parse_batch_mixed

    assert_equal "foobar", responses.find { |r| r["id"] == "9" }["result"]
  end

  def test_spec_batch_all_notifications
    request = '[{"jsonrpc":"2.0","method":"notify_hello","params":[7]},' \
              '{"jsonrpc":"2.0","method":"notify_hello","params":[7]}]'

    assert_nil @server.handle(request)
  end

  private

  def parse_batch_mixed
    json = '[{"jsonrpc":"2.0","method":"sum","params":[1,2,4],"id":"1"},' \
           '{"jsonrpc":"2.0","method":"notify_hello","params":[7]},' \
           '{"jsonrpc":"2.0","method":"subtract","params":[42,23],"id":"2"},' \
           '{"foo":"boo"},' \
           '{"jsonrpc":"2.0","method":"nonexistent","params":[5],"id":"5"},' \
           '{"jsonrpc":"2.0","method":"foobar","id":"9"}]'
    JSON.parse(@server.handle(json))
  end
end

class TestIntegration < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator, namespace: "calc")
    @server.expose(Greeter.new("Hey"), namespace: "greeter")
    @server.expose_method("ping") { "pong" }
  end

  def test_discover_lists_all_methods
    result = call(@server, "rpc.discover", id: 1)
    method_names = result["methods"].map { |m| m["name"] }

    assert_includes method_names, "calc.add"
    assert_includes method_names, "greeter.greet"
    assert_includes method_names, "ping"
  end

  def test_call_namespaced_module
    assert_equal 42, call(@server, "calc.add", params: [40, 2], id: 1)
  end

  def test_call_namespaced_instance_with_kwargs
    assert_equal "Hey, World!", call(@server, "greeter.greet", params: { "name" => "World" }, id: 1)
  end

  def test_call_custom_method
    assert_equal "pong", call(@server, "ping", id: 1)
  end

  def test_middleware_auth_pattern
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use do |request, next_call|
      raise Reclamo::Core::ApplicationError.new(code: 401, message: "Unauthorized") if request.method_name == "divide"

      next_call.call
    end

    assert_equal 5, call(server, "add", params: [2, 3], id: 1)
    assert_equal 401, call_error(server, "divide", params: [10, 2], id: 2)["code"]
  end

  private

  def call(server, method, id:, params: nil)
    req = { "jsonrpc" => "2.0", "method" => method, "id" => id }
    req["params"] = params if params
    JSON.parse(server.handle(JSON.generate(req)))["result"]
  end

  def call_error(server, method, id:, params: nil)
    req = { "jsonrpc" => "2.0", "method" => method, "id" => id }
    req["params"] = params if params
    JSON.parse(server.handle(JSON.generate(req)))["error"]
  end
end
