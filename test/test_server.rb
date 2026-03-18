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

class TestHandler < Minitest::Test
  def test_method_query
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert handler.method?("add")
    refute handler.method?("nonexistent")
  end

  def test_does_not_expose_inherited_object_methods
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))

    refute handler.method?("class")
    refute handler.method?("object_id")
  end
end
