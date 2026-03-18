# frozen_string_literal: true

require "test_helper"
require "json"

class TestRequestTimeout < Minitest::Test
  def test_slow_handler_times_out
    server = Reclamo::Server.new(timeout: 0.1)
    server.expose_method("slow") { sleep 0.5 }

    response = call(server, "slow")
    assert_equal(-32_001, response["error"]["code"])
    assert_equal "Request timeout", response["error"]["message"]
  end

  def test_fast_handler_succeeds_within_timeout
    server = Reclamo::Server.new(timeout: 5)
    server.expose(Calculator)

    response = call(server, "add", [2, 3])
    assert_equal 5, response["result"]
  end

  def test_no_timeout_by_default
    server = Reclamo::Server.new
    server.expose(Calculator)

    response = call(server, "add", [1, 2])
    assert_equal 3, response["result"]
  end

  def test_timeout_notification_returns_nil
    server = Reclamo::Server.new(timeout: 0.1)
    server.expose_method("slow") { sleep 0.5 }

    request = { "jsonrpc" => "2.0", "method" => "slow" }
    assert_nil server.handle(JSON.generate(request))
  end

  def test_timeout_triggers_error_hook
    server = Reclamo::Server.new(timeout: 0.1)
    server.expose_method("slow") { sleep 0.5 }
    captured_error = nil
    server.on(:error) { |_req, err, _dur| captured_error = err }

    call(server, "slow")
    assert_instance_of Reclamo::RequestTimeout, captured_error
  end

  def test_request_timeout_is_a_server_error
    error = Reclamo::RequestTimeout.new
    assert_kind_of Reclamo::ServerError, error
    assert_equal(-32_001, error.code)
  end

  def test_timeout_reader
    assert_equal 5, Reclamo::Server.new(timeout: 5).timeout
  end

  def test_timeout_defaults_to_nil
    assert_nil Reclamo::Server.new.timeout
  end

  def test_request_timeout_constant
    assert_equal(-32_001, Reclamo::REQUEST_TIMEOUT)
  end

  private

  def call(server, method, params = nil)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(server.handle(JSON.generate(request)))
  end
end
