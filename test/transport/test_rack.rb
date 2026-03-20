# frozen_string_literal: true

require "test_helper"
require "ultimate_json_rpc/transport/rack"
require "json"

class TestRack < Minitest::Test
  def setup
    server = UltimateJsonRpc::Server.new(name: "Test API")
    server.expose(Calculator)
    @app = UltimateJsonRpc::Transport::Rack.new(server)
  end

  def test_post_with_valid_request_returns_ok
    status, headers, body = @app.call(rack_env("add", [2, 3]))

    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    response = JSON.parse(body.first)
    assert_equal 5, response["result"]
    assert_equal 1, response["id"]
  end

  def test_notification_returns_no_content
    env = rack_env_raw({ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] })
    status, _headers, body = @app.call(env)

    assert_equal 204, status
    assert_empty body
  end

  def test_get_returns_method_not_allowed
    env = { "REQUEST_METHOD" => "GET", "rack.input" => StringIO.new("") }
    status, headers, body = @app.call(env)

    assert_equal 405, status
    assert_equal "POST", headers["allow"]
    assert_equal "application/json", headers["content-type"]
    assert_includes body.first, "Method Not Allowed"
  end

  def test_put_returns_method_not_allowed
    env = { "REQUEST_METHOD" => "PUT", "rack.input" => StringIO.new("") }
    status, = @app.call(env)

    assert_equal 405, status
  end

  def test_delete_returns_method_not_allowed
    env = { "REQUEST_METHOD" => "DELETE", "rack.input" => StringIO.new("") }
    status, = @app.call(env)

    assert_equal 405, status
  end

  def test_invalid_json_returns_parse_error
    env = { "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new("not json") }
    status, headers, body = @app.call(env)

    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    response = JSON.parse(body.first)
    assert_equal(-32_700, response["error"]["code"])
  end

  def test_batch_request
    batch = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    env = rack_env_raw(batch)
    status, _, body = @app.call(env)

    assert_equal 200, status
    responses = JSON.parse(body.first)
    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_batch_of_notifications_returns_no_content
    batch = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] }
    ]
    env = rack_env_raw(batch)
    status, _, body = @app.call(env)

    assert_equal 204, status
    assert_empty body
  end

  def test_method_not_found
    status, _, body = @app.call(rack_env("nonexistent"))

    assert_equal 200, status
    response = JSON.parse(body.first)
    assert_equal(-32_601, response["error"]["code"])
  end

  def test_head_returns_ok_with_empty_body
    env = { "REQUEST_METHOD" => "HEAD", "rack.input" => StringIO.new("") }
    status, headers, body = @app.call(env)

    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    assert_empty body
  end

  def test_method_not_allowed_returns_jsonrpc_error
    env = { "REQUEST_METHOD" => "GET", "rack.input" => StringIO.new("") }
    _, _, body = @app.call(env)
    response = JSON.parse(body.first)

    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_600, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_freeze_delegates_to_server
    app = UltimateJsonRpc::Transport::Rack.new(UltimateJsonRpc::Server.new)
    app.freeze

    assert_predicate app, :frozen?
  end

  def test_frozen_rack_app_handles_requests
    app = UltimateJsonRpc::Transport::Rack.new(UltimateJsonRpc::Server.new.tap { |s| s.expose(Calculator) })
    app.freeze

    status, _, body = app.call(rack_env("add", [2, 3]))
    assert_equal 200, status
    assert_equal 5, JSON.parse(body.first)["result"]
  end

  def test_response_headers_are_mutable
    _status, headers, _body = @app.call(rack_env("add", [2, 3]))
    headers["content-length"] = "42"
    assert_equal "42", headers["content-length"]
  end

  def test_head_response_headers_are_mutable
    env = { "REQUEST_METHOD" => "HEAD", "rack.input" => StringIO.new("") }
    _status, headers, _body = @app.call(env)
    headers["content-length"] = "0"
    assert_equal "0", headers["content-length"]
  end

  def test_method_not_allowed_headers_are_mutable
    env = { "REQUEST_METHOD" => "GET", "rack.input" => StringIO.new("") }
    _status, headers, _body = @app.call(env)
    headers["content-length"] = "99"
    assert_equal "99", headers["content-length"]
  end

  def test_unsupported_media_type
    env = { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "text/plain",
            "rack.input" => StringIO.new('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}') }
    status, headers, body = @app.call(env)

    assert_equal 415, status
    assert_equal "application/json", headers["content-type"]
    response = JSON.parse(body.first)
    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_600, response["error"]["code"])
    assert_includes response["error"]["message"], "Unsupported Media Type"
    assert_nil response["id"]
  end

  def test_unsupported_media_type_with_xml
    env = { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "application/xml",
            "rack.input" => StringIO.new("") }
    status, = @app.call(env)

    assert_equal 415, status
  end

  def test_application_json_with_charset_is_accepted
    env = { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "application/json; charset=utf-8",
            "rack.input" => StringIO.new(JSON.generate({ "jsonrpc" => "2.0", "method" => "add",
                                                         "params" => [1, 2], "id" => 1 })) }
    status, = @app.call(env)

    assert_equal 200, status
  end

  def test_unsupported_media_type_headers_are_mutable
    env = { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "text/plain",
            "rack.input" => StringIO.new("") }
    _status, headers, _body = @app.call(env)
    headers["content-length"] = "99"
    assert_equal "99", headers["content-length"]
  end

  def test_nil_rack_input
    env = { "REQUEST_METHOD" => "POST", "rack.input" => nil }
    status, _, body = @app.call(env)

    assert_equal 200, status
    response = JSON.parse(body.first)
    assert_equal(-32_700, response["error"]["code"])
  end

  def test_empty_body
    env = { "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new("") }
    status, _, body = @app.call(env)

    assert_equal 200, status
    response = JSON.parse(body.first)
    assert_equal(-32_700, response["error"]["code"])
  end

  private

  def rack_env(method_name, params = nil, id: 1)
    request = { "jsonrpc" => "2.0", "method" => method_name, "id" => id }
    request["params"] = params if params
    rack_env_raw(request)
  end

  def rack_env_raw(data)
    { "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new(JSON.generate(data)) }
  end
end
