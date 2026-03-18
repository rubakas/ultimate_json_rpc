# frozen_string_literal: true

require "test_helper"
require "json"

module Calculator
  def self.add(left, right)
    left + right
  end

  def self.divide(numerator, denominator)
    raise ZeroDivisionError, "division by zero" if denominator.zero?

    numerator.to_f / denominator
  end
end

class Greeter
  def initialize(greeting)
    @greeting = greeting
  end

  def greet(name:)
    "#{@greeting}, #{name}!"
  end

  def hello
    "hello"
  end
end

class TestServerCalls < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
    @server.expose(Greeter.new("Hi"), namespace: "greeter")
  end

  def test_successful_method_call
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal 5, response["result"]
    assert_equal 1, response["id"]
  end

  def test_namespaced_method_call
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "name" => "World" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "Hi, World!", response["result"]
  end

  def test_method_call_without_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.hello", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "hello", response["result"]
  end

  def test_method_call_with_keyword_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "name" => "Alice" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "Hi, Alice!", response["result"]
  end

  def test_string_id
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => "abc" }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "abc", response["id"]
    assert_equal 3, response["result"]
  end

  def test_null_id
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => nil }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_nil response["id"]
    assert_equal 3, response["result"]
  end

  def test_result_can_be_nil
    server = Reclamo::Server.new
    target = Object.new
    def target.noop; end
    server.expose(target)

    request = { "jsonrpc" => "2.0", "method" => "noop", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_nil response["result"]
    assert_equal 1, response["id"]
  end

  def test_methods_list
    methods = @server.methods_list

    assert_includes methods, "add"
    assert_includes methods, "divide"
    assert_includes methods, "greeter.greet"
    assert_includes methods, "greeter.hello"
  end

  def test_expose_returns_self
    server = Reclamo::Server.new

    assert_equal server, server.expose(Calculator)
  end
end

class TestServerErrors < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_method_not_found
    request = { "jsonrpc" => "2.0", "method" => "nonexistent", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
    assert_equal "Method not found", response["error"]["message"]
  end

  def test_parse_error
    response = JSON.parse(@server.handle("not json"))

    assert_equal(-32_700, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_invalid_request_missing_method
    request = { "jsonrpc" => "2.0", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_invalid_request_wrong_version
    request = { "jsonrpc" => "1.0", "method" => "add", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_internal_error
    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [1, 0], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal "division by zero", response["error"]["data"]
  end

  def test_invalid_params_type
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => "invalid", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_invalid_request_not_a_hash
    response = JSON.parse(@server.handle(JSON.generate("just a string")))

    assert_equal(-32_600, response["error"]["code"])
  end
end

class TestServerNotifications < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_notification_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }

    assert_nil @server.handle(JSON.generate(request))
  end

  def test_notification_error_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [1, 0] }

    assert_nil @server.handle(JSON.generate(request))
  end

  def test_notification_method_not_found_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "nonexistent" }

    assert_nil @server.handle(JSON.generate(request))
  end
end

class TestServerBatch < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_batch_request
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_batch_with_notification
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 1, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_empty_batch
    response = JSON.parse(@server.handle("[]"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_batch_all_notifications
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    ]

    assert_nil @server.handle(JSON.generate(requests))
  end

  def test_batch_with_invalid_items
    requests = [
      1,
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal(-32_600, responses[0]["error"]["code"])
    assert_equal 3, responses[1]["result"]
  end
end

class TestServerExposeMethod < Minitest::Test
  def test_expose_block_as_method
    server = Reclamo::Server.new
    server.expose_method("double") { |num| num * 2 }

    request = { "jsonrpc" => "2.0", "method" => "double", "params" => [5], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 10, response["result"]
  end

  def test_expose_block_with_keyword_params
    server = Reclamo::Server.new
    server.expose_method("greet") { |name:, greeting: "Hello"| "#{greeting}, #{name}!" }

    request = { "jsonrpc" => "2.0", "method" => "greet",
                "params" => { "name" => "World" }, "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal "Hello, World!", response["result"]
  end

  def test_expose_method_returns_self
    server = Reclamo::Server.new

    assert_equal server, server.expose_method("noop") { nil }
  end

  def test_expose_method_rejects_rpc_prefix
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose_method("rpc.foo") { "bar" }
    end
  end

  def test_expose_method_without_block_raises
    handler = Reclamo::Handler.new

    assert_raises(ArgumentError) { handler.expose_method("foo") }
  end
end

class TestServerDiscover < Minitest::Test
  def test_rpc_discover_returns_methods
    server = Reclamo::Server.new
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal({ "methods" => %w[add divide] }, response["result"])
  end

  def test_rpc_discover_includes_custom_methods
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_includes response["result"]["methods"], "ping"
  end
end

class TestServerApplicationError < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose_method("fail_custom") do
      raise Reclamo::ApplicationError.new(42, "Custom error", { "detail" => "something went wrong" })
    end
    @server.expose_method("fail_simple") do
      raise Reclamo::ApplicationError.new(100, "Simple failure")
    end
  end

  def test_application_error_with_data
    request = { "jsonrpc" => "2.0", "method" => "fail_custom", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal 42, response["error"]["code"]
    assert_equal "Custom error", response["error"]["message"]
    assert_equal({ "detail" => "something went wrong" }, response["error"]["data"])
  end

  def test_application_error_without_data
    request = { "jsonrpc" => "2.0", "method" => "fail_simple", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal 100, response["error"]["code"]
    assert_equal "Simple failure", response["error"]["message"]
    refute response["error"].key?("data")
  end

  def test_application_error_notification_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "fail_custom" }

    assert_nil @server.handle(JSON.generate(request))
  end
end

class TestRequestValidation < Minitest::Test
  def test_empty_method_name_is_invalid
    server = Reclamo::Server.new
    request = { "jsonrpc" => "2.0", "method" => "", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end
end

class TestServerMethodFiltering < Minitest::Test
  def test_expose_only
    server = Reclamo::Server.new
    server.expose(Calculator, only: [:add])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_except
    server = Reclamo::Server.new
    server.expose(Calculator, except: [:divide])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_only_with_strings
    server = Reclamo::Server.new
    server.expose(Calculator, only: ["add"])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_only_and_except_raises
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose(Calculator, only: [:add], except: [:divide])
    end
  end

  def test_expose_only_with_namespace
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math", only: [:add])

    assert_includes server.methods_list, "math.add"
    refute_includes server.methods_list, "math.divide"
  end

  def test_filtered_method_returns_not_found
    server = Reclamo::Server.new
    server.expose(Calculator, only: [:add])

    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [10, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
  end
end

class TestServerMiddleware < Minitest::Test
  def test_middleware_can_transform_result
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use do |_request, next_call|
      result = next_call.call
      result * 10
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 50, response["result"]
  end

  def test_middleware_can_reject_request
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use do |request, next_call|
      raise Reclamo::ApplicationError.new(403, "Forbidden") if request.method_name == "divide"

      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [10, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 403, response["error"]["code"]
    assert_equal "Forbidden", response["error"]["message"]
  end

  def test_middleware_chain_order
    log = []
    server = build_logging_server(log)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert_equal %w[first:before second:before second:after first:after], log
  end

  private

  def build_logging_server(log)
    server = Reclamo::Server.new
    server.expose(Calculator)
    add_logging_middleware(server, log, %w[first second])
    server
  end

  def add_logging_middleware(server, log, names)
    names.each do |name|
      server.use do |_request, next_call|
        log << "#{name}:before"
        next_call.call.tap { log << "#{name}:after" }
      end
    end
  end

  public

  def test_middleware_receives_request
    server = Reclamo::Server.new
    server.expose(Calculator)
    captured_method = nil

    server.use do |request, next_call|
      captured_method = request.method_name
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert_equal "add", captured_method
  end

  def test_use_returns_self
    server = Reclamo::Server.new

    result = server.use { |_req, next_call| next_call.call }
    assert_equal server, result
  end

  def test_use_without_block_raises
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.use }
  end

  def test_middleware_not_called_for_invalid_requests
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false

    server.use do |_request, next_call|
      called = true
      next_call.call
    end

    server.handle("not json")

    refute called
  end
end

class TestHandler < Minitest::Test
  def test_method_query
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert handler.method?("add")
    refute handler.method?("nonexistent")
  end

  def test_expose_rejects_rpc_namespace
    handler = Reclamo::Handler.new

    assert_raises(ArgumentError) { handler.expose(Calculator, namespace: "rpc") }
  end

  def test_does_not_expose_inherited_object_methods
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))

    refute handler.method?("class")
    refute handler.method?("object_id")
  end
end
