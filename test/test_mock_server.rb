# frozen_string_literal: true

require "test_helper"
require "reclamo/mock_server"
require "json"

class TestMockServer < Minitest::Test
  def test_stub_returns_canned_result
    mock = Reclamo::MockServer.new
    mock.stub("add", [2, 3], 5)
    response = call(mock, "add", [2, 3])

    assert_equal 5, response["result"]
  end

  def test_stub_different_params_different_results
    mock = Reclamo::MockServer.new
    mock.stub("add", [2, 3], 5)
    mock.stub("add", [10, 20], 30)

    assert_equal 5, call(mock, "add", [2, 3])["result"]
    assert_equal 30, call(mock, "add", [10, 20])["result"]
  end

  def test_stub_with_hash_params
    mock = Reclamo::MockServer.new
    mock.stub("greet", { "name" => "Alice" }, "Hi Alice")
    response = call(mock, "greet", { "name" => "Alice" })

    assert_equal "Hi Alice", response["result"]
  end

  def test_stub_with_symbol_keys_matches_string_keys
    mock = Reclamo::MockServer.new
    mock.stub("greet", { name: "Alice" }, "Hi Alice")
    response = call(mock, "greet", { "name" => "Alice" })

    assert_equal "Hi Alice", response["result"]
  end

  def test_stub_with_nil_params
    mock = Reclamo::MockServer.new
    mock.stub("ping", nil, "pong")
    response = call_no_params(mock, "ping")

    assert_equal "pong", response["result"]
  end

  def test_no_stub_returns_method_not_found
    mock = Reclamo::MockServer.new
    response = call(mock, "unknown", [1])

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_wrong_params_returns_method_not_found
    mock = Reclamo::MockServer.new
    mock.stub("add", [2, 3], 5)
    response = call(mock, "add", [99, 99])

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_stub_any_matches_all_params
    mock = Reclamo::MockServer.new
    mock.stub_any("echo", "stubbed")

    assert_equal "stubbed", call(mock, "echo", [1])["result"]
    assert_equal "stubbed", call(mock, "echo", [2, 3])["result"]
    assert_equal "stubbed", call(mock, "echo", { "x" => 1 })["result"]
  end

  def test_exact_stub_takes_precedence_over_any
    mock = Reclamo::MockServer.new
    mock.stub_any("add", "any")
    mock.stub("add", [2, 3], 5)

    assert_equal 5, call(mock, "add", [2, 3])["result"]
    assert_equal "any", call(mock, "add", [99, 99])["result"]
  end

  def test_notification_returns_nil
    mock = Reclamo::MockServer.new
    mock.stub("ping", nil, "pong")
    request = { "jsonrpc" => "2.0", "method" => "ping" }

    assert_nil mock.handle(JSON.generate(request))
  end

  def test_batch_request
    mock = Reclamo::MockServer.new
    mock.stub("add", [1, 2], 3)
    mock.stub("add", [3, 4], 7)
    batch = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(mock.handle(JSON.generate(batch)))

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_parse_error
    mock = Reclamo::MockServer.new
    response = JSON.parse(mock.handle("not json"))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_invalid_request
    mock = Reclamo::MockServer.new
    response = JSON.parse(mock.handle('"just a string"'))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_chainable
    mock = Reclamo::MockServer.new
    result = mock.stub("a", nil, 1).stub("b", nil, 2).stub_any("c", 3)

    assert_instance_of Reclamo::MockServer, result
  end

  def test_complex_result
    mock = Reclamo::MockServer.new
    mock.stub("info", nil, { "status" => "ok", "items" => [1, 2, 3] })
    response = call_no_params(mock, "info")

    assert_equal "ok", response["result"]["status"]
    assert_equal [1, 2, 3], response["result"]["items"]
  end

  def test_custom_json_adapter
    adapter = Module.new do
      def self.parse(str) = JSON.parse(str)
      def self.generate(obj) = JSON.generate(obj)
    end
    mock = Reclamo::MockServer.new(json: adapter)
    mock.stub("add", [2, 3], 5)
    response = call(mock, "add", [2, 3])
    assert_equal 5, response["result"]
  end

  def test_invalid_id_type_returns_invalid_request
    mock = Reclamo::MockServer.new
    mock.stub("add", [1, 2], 3)

    response = JSON.parse(mock.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":[1]}'))
    assert_equal(-32_600, response["error"]["code"])

    response = JSON.parse(mock.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":true}'))
    assert_equal(-32_600, response["error"]["code"])
  end

  def test_handle_parsed
    mock = Reclamo::MockServer.new
    mock.stub("add", [2, 3], 5)
    data = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(mock.handle_parsed(data))

    assert_equal 5, response["result"]
  end

  private

  def call(mock, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(mock.handle(JSON.generate(request)))
  end

  def call_no_params(mock, method)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    JSON.parse(mock.handle(JSON.generate(request)))
  end
end
