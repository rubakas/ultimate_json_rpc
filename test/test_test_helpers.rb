# frozen_string_literal: true

require "test_helper"
require "reclamo/test_helpers"

class TestTestHelpers < Minitest::Test
  include Reclamo::TestHelpers

  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_rpc_call_returns_parsed_response
    response = rpc_call(@server, "add", params: [2, 3])

    assert_equal 5, response["result"]
    assert_equal 1, response["id"]
  end

  def test_rpc_call_with_custom_id
    response = rpc_call(@server, "add", params: [2, 3], id: 42)

    assert_equal 42, response["id"]
  end

  def test_rpc_call_without_params
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))

    response = rpc_call(server, "hello")

    assert_equal "hello", response["result"]
  end

  def test_rpc_call_error
    response = rpc_call(@server, "nonexistent")

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_rpc_notify_returns_nil
    assert_nil rpc_notify(@server, "add", params: [1, 2])
  end

  def test_rpc_batch_returns_parsed_responses
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = rpc_batch(@server, *requests)

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_rpc_batch_all_notifications_returns_nil
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    ]

    assert_nil rpc_batch(@server, *requests)
  end

  # assert_rpc_success

  def test_assert_rpc_success_passes_for_success_response
    response = rpc_call(@server, "add", params: [2, 3])
    assert_rpc_success(response)
  end

  def test_assert_rpc_success_with_expected_value
    response = rpc_call(@server, "add", params: [2, 3])
    assert_rpc_success(response, 5)
  end

  def test_assert_rpc_success_fails_for_error_response
    response = rpc_call(@server, "nonexistent")
    assert_raises(Minitest::Assertion) { assert_rpc_success(response) }
  end

  def test_assert_rpc_success_fails_for_wrong_value
    response = rpc_call(@server, "add", params: [2, 3])
    assert_raises(Minitest::Assertion) { assert_rpc_success(response, 99) }
  end

  def test_assert_rpc_success_with_nil_result
    server = Reclamo::Server.new
    server.expose_method("noop") { nil }
    response = rpc_call(server, "noop")
    assert_rpc_success(response, nil)
  end

  # assert_rpc_error

  def test_assert_rpc_error_passes_for_error_response
    response = rpc_call(@server, "nonexistent")
    assert_rpc_error(response)
  end

  def test_assert_rpc_error_with_code
    response = rpc_call(@server, "nonexistent")
    assert_rpc_error(response, code: -32_601)
  end

  def test_assert_rpc_error_with_message
    response = rpc_call(@server, "nonexistent")
    assert_rpc_error(response, message: "Method not found")
  end

  def test_assert_rpc_error_with_code_and_message
    response = rpc_call(@server, "nonexistent")
    assert_rpc_error(response, code: -32_601, message: "Method not found")
  end

  def test_assert_rpc_error_fails_for_success_response
    response = rpc_call(@server, "add", params: [1, 2])
    assert_raises(Minitest::Assertion) { assert_rpc_error(response) }
  end

  def test_assert_rpc_error_fails_for_wrong_code
    response = rpc_call(@server, "nonexistent")
    assert_raises(Minitest::Assertion) { assert_rpc_error(response, code: 999) }
  end

  # assert_rpc_notification

  def test_assert_rpc_notification_passes
    assert_rpc_notification(@server, "add", params: [1, 2])
  end

  def test_assert_rpc_notification_without_params
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    assert_rpc_notification(server, "hello")
  end
end
