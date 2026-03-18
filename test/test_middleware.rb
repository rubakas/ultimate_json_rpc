# frozen_string_literal: true

require "test_helper"
require "json"

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

  def test_middleware_runs_for_notifications
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false

    server.use do |_request, next_call|
      called = true
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    assert_nil server.handle(JSON.generate(request))
    assert called
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
end

class TestServerMiddlewareEdgeCases < Minitest::Test
  def test_middleware_runs_for_rpc_discover
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false
    server.use { |_req, n| (called = true) && n.call }

    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))
    assert called
    assert response["result"].key?("methods")
  end

  def test_request_params_are_frozen
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use do |request, next_call|
      assert_predicate request.params, :frozen?
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))
  end

  def test_middleware_unexpected_error_returns_internal_error
    server = Reclamo::Server.new(expose_errors: true)
    server.expose(Calculator)
    server.use { |_request, _next_call| raise "middleware broke" }

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal "middleware broke", response["error"]["data"]
  end

  def test_invalid_request_from_middleware_returns_internal_error
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |_request, _next_call| raise Reclamo::InvalidRequest }

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 42 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal 42, response["id"]
  end

  def test_nested_request_params_are_deeply_frozen
    server = Reclamo::Server.new
    server.expose(Calculator)
    nested_frozen = nil

    server.use do |request, next_call|
      nested_frozen = request.params[0].frozen?
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [{ "a" => 1 }, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert nested_frozen, "nested params should be deeply frozen"
  end

  def test_server_error_from_middleware
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |_request, _next_call| raise Reclamo::ServerError.new(-32_050, "Rate limited") }

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_050, response["error"]["code"])
    assert_equal "Rate limited", response["error"]["message"]
  end

  def test_application_error_from_middleware
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use do |request, _next_call|
      raise Reclamo::ApplicationError.new(403, "Forbidden") if request.method_name == "add"
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 403, response["error"]["code"]
    assert_equal "Forbidden", response["error"]["message"]
  end

  def test_middleware_short_circuit_returns_custom_result
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |_request, _next_call| "intercepted" }

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal "intercepted", response["result"]
    refute response.key?("error")
  end

  def test_middleware_short_circuit_notification_returns_nil
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |_request, _next_call| "intercepted" }

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }

    assert_nil server.handle(JSON.generate(request))
  end

  def test_middleware_can_write_and_read_request_context
    server = Reclamo::Server.new
    server.expose(Calculator)
    captured_user = nil
    server.use { |req, n| req.context[:user] = "alice" and n.call }
    server.use { |req, n| captured_user = req.context[:user] and n.call }
    server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }))
    assert_equal "alice", captured_user
  end
end
