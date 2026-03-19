# frozen_string_literal: true

require "test_helper"
require "json"

class TestServerErrors < Minitest::Test
  def setup
    @server = Reclamo::Server.new(expose_errors: true)
    @server.expose(Calculator)
  end

  def test_method_not_found
    request = { "jsonrpc" => "2.0", "method" => "nonexistent", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
    assert_equal "Method not found", response["error"]["message"]
    assert_equal "nonexistent", response["error"]["data"]
  end

  def test_parse_error
    response = JSON.parse(@server.handle("not json"))

    assert_equal(-32_700, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_handle_nil_input
    response = JSON.parse(@server.handle(nil))

    assert_equal(-32_700, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_valid_json_false_returns_invalid_request
    response = JSON.parse(@server.handle("false"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_valid_json_null_returns_invalid_request
    response = JSON.parse(@server.handle("null"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_valid_json_number_returns_invalid_request
    response = JSON.parse(@server.handle("42"))

    assert_equal(-32_600, response["error"]["code"])
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

  def test_non_serializable_result_returns_internal_error
    server = Reclamo::Server.new
    circ = {}
    circ["self"] = circ
    server.expose_method("bad") { circ }

    request = { "jsonrpc" => "2.0", "method" => "bad", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal 1, response["id"]
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

  def test_over_nested_params_returns_invalid_request
    nested = "leaf"
    32.times { nested = { "n" => nested } }
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => nested, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end
end

class TestServerApplicationError < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose_method("fail_custom") do
      raise Reclamo::ApplicationError.new(
        code: 42, message: "Custom error", data: { "detail" => "something went wrong" }
      )
    end
    @server.expose_method("fail_simple") do
      raise Reclamo::ApplicationError.new(code: 100, message: "Simple failure")
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

  def test_application_error_with_false_data
    server = Reclamo::Server.new
    server.expose_method("fail_false") do
      raise Reclamo::ApplicationError.new(code: 42, message: "Boolean error", data: false)
    end

    request = { "jsonrpc" => "2.0", "method" => "fail_false", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal false, response["error"]["data"]
  end

  def test_application_error_with_zero_data
    server = Reclamo::Server.new
    server.expose_method("fail_zero") do
      raise Reclamo::ApplicationError.new(code: 42, message: "Zero error", data: 0)
    end

    request = { "jsonrpc" => "2.0", "method" => "fail_zero", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 0, response["error"]["data"]
  end

  def test_application_error_rejects_reserved_codes
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: -32_700, message: "Parse error") }
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: -32_600, message: "Invalid") }
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: -32_000, message: "Server error") }
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: -32_768, message: "Edge of range") }
  end

  def test_application_error_server_range_mentions_server_error
    err = assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: -32_050, message: "In range") }
    assert_match(/ServerError/, err.message)
  end

  def test_application_error_allows_non_reserved_codes
    err = Reclamo::ApplicationError.new(code: -31_999, message: "Just outside range")
    assert_equal(-31_999, err.code)

    err2 = Reclamo::ApplicationError.new(code: -32_769, message: "Below range")
    assert_equal(-32_769, err2.code)

    err3 = Reclamo::ApplicationError.new(code: 1, message: "Positive code")
    assert_equal 1, err3.code
  end

  def test_application_error_rejects_non_integer_code
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: "42", message: "String code") }
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: 1.5, message: "Float code") }
    assert_raises(ArgumentError) { Reclamo::ApplicationError.new(code: nil, message: "Nil code") }
  end
end

class TestInvalidParams < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose_method("validate") do |age:|
      raise Reclamo::InvalidParams, "age must be positive" unless age.positive?

      age
    end
  end

  def test_invalid_params_returns_correct_error
    request = { "jsonrpc" => "2.0", "method" => "validate",
                "params" => { "age" => -1 }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
    assert_equal "Invalid params", response["error"]["message"]
    assert_equal "age must be positive", response["error"]["data"]
  end

  def test_invalid_params_notification_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "validate", "params" => { "age" => -1 } }
    assert_nil @server.handle(JSON.generate(request))
  end
end

class TestServerError < Minitest::Test
  def test_server_error_allows_server_error_range
    err = Reclamo::ServerError.new(code: -32_000, message: "Server busy")
    assert_equal(-32_000, err.code)
    assert_equal "Server busy", err.message

    err2 = Reclamo::ServerError.new(code: -32_099, message: "Edge of range")
    assert_equal(-32_099, err2.code)
  end

  def test_server_error_rejects_codes_outside_range
    assert_raises(ArgumentError) { Reclamo::ServerError.new(code: -32_100, message: "Too low") }
    assert_raises(ArgumentError) { Reclamo::ServerError.new(code: -31_999, message: "Too high") }
    assert_raises(ArgumentError) { Reclamo::ServerError.new(code: 1, message: "Positive") }
  end

  def test_server_error_with_data
    err = Reclamo::ServerError.new(code: -32_000, message: "Busy", data: { "retry_after" => 5 })
    assert_equal({ "retry_after" => 5 }, err.rpc_data)
  end

  def test_server_error_in_handler
    server = Reclamo::Server.new
    server.expose_method("shutdown") do
      raise Reclamo::ServerError.new(code: -32_001, message: "Server shutting down")
    end

    request = { "jsonrpc" => "2.0", "method" => "shutdown", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_001, response["error"]["code"])
    assert_equal "Server shutting down", response["error"]["message"]
  end

  def test_server_error_notification_returns_nil
    server = Reclamo::Server.new
    server.expose_method("shutdown") do
      raise Reclamo::ServerError.new(code: -32_001, message: "Shutting down")
    end

    request = { "jsonrpc" => "2.0", "method" => "shutdown" }
    assert_nil server.handle(JSON.generate(request))
  end
end

class TestExposeErrorsPredicate < Minitest::Test
  def test_expose_errors_predicate
    refute Reclamo::Server.new.expose_errors?
    assert Reclamo::Server.new(expose_errors: true).expose_errors?
  end
end

class TestRequestIdValidation < Minitest::Test
  def test_empty_method_name_is_invalid
    server = Reclamo::Server.new
    request = { "jsonrpc" => "2.0", "method" => "", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_id_as_array_is_invalid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => [1] }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_id_as_object_is_invalid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => { "x" => 1 } }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_id_as_boolean_is_invalid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => true }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_id_as_integer_is_valid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 42 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 3, response["result"]
    assert_equal 42, response["id"]
  end

  def test_id_as_float_is_valid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1.0 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 3, response["result"]
  end

  def test_id_zero_is_valid
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 0 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 3, response["result"]
    assert_equal 0, response["id"]
  end

  def test_boolean_id_returns_null_in_error
    server = Reclamo::Server.new
    server.expose(Calculator)
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => true }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_invalid_request_preserves_valid_id
    server = Reclamo::Server.new
    request = { "jsonrpc" => "1.0", "method" => "add", "id" => 99 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal 99, response["id"]
  end

  def test_invalid_request_nullifies_bad_id_type
    server = Reclamo::Server.new
    request = { "jsonrpc" => "2.0", "method" => "", "id" => [1, 2, 3] }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_600, response["error"]["code"])
    assert_nil response["id"]
  end
end

class TestServerParamErrors < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
    @server.expose(Greeter.new("Hi"), namespace: "greeter")
  end

  def test_too_many_positional_args_returns_invalid_params
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2, 3], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
  end

  def test_too_few_positional_args_returns_invalid_params
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
  end

  def test_missing_required_keyword_returns_invalid_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "wrong_key" => "World" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
  end

  def test_unknown_rpc_method_returns_method_not_found
    request = { "jsonrpc" => "2.0", "method" => "rpc.listMethods", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_empty_array_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.hello", "params" => [], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "hello", response["result"]
  end

  def test_empty_hash_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.hello", "params" => {}, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "hello", response["result"]
  end

  def test_extra_keyword_args_returns_invalid_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "name" => "World", "extra" => "ignored" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
  end

  def test_success_response_has_no_error_key
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert response.key?("result")
    refute response.key?("error")
  end

  def test_error_response_has_no_result_key
    request = { "jsonrpc" => "2.0", "method" => "nonexistent", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert response.key?("error")
    refute response.key?("result")
  end
end

class TestExposeErrorsOption < Minitest::Test
  def test_default_hides_internal_error_messages
    server = Reclamo::Server.new
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [1, 0], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal "Internal server error", response["error"]["data"]
  end

  def test_expose_errors_shows_internal_error_messages
    server = Reclamo::Server.new(expose_errors: true)
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [1, 0], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal "division by zero", response["error"]["data"]
  end

  def test_application_error_always_exposed
    server = Reclamo::Server.new
    server.expose_method("fail") { raise Reclamo::ApplicationError.new(code: 42, message: "Custom", data: "detail") }

    request = { "jsonrpc" => "2.0", "method" => "fail", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 42, response["error"]["code"]
    assert_equal "detail", response["error"]["data"]
  end

  def test_server_error_always_exposed
    server = Reclamo::Server.new
    server.expose_method("fail") { raise Reclamo::ServerError.new(code: -32_001, message: "Shutting down", data: "retry") }

    request = { "jsonrpc" => "2.0", "method" => "fail", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_001, response["error"]["code"])
    assert_equal "retry", response["error"]["data"]
  end

  def test_invalid_params_always_exposed
    server = Reclamo::Server.new
    server.expose_method("validate") do |age:|
      raise Reclamo::InvalidParams, "bad" unless age.positive?

      age
    end

    request = { "jsonrpc" => "2.0", "method" => "validate", "params" => { "age" => -1 }, "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
    assert_equal "bad", response["error"]["data"]
  end

  def test_method_not_found_always_exposed
    server = Reclamo::Server.new

    request = { "jsonrpc" => "2.0", "method" => "missing", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
    assert_equal "missing", response["error"]["data"]
  end

  def test_argument_error_hidden_by_default
    server = Reclamo::Server.new
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
    assert_equal "Invalid method parameters", response["error"]["data"]
  end
end

class TestInvalidRequestFromMiddleware < Minitest::Test
  def test_middleware_raising_invalid_request_returns_invalid_request_code
    server = Reclamo::Server.new(expose_errors: true)
    server.expose(Calculator)
    server.use { |_req, _nxt| raise Reclamo::InvalidRequest, "bad request from middleware" }

    request = '{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal "bad request from middleware", response["error"]["data"]
  end

  def test_middleware_raising_invalid_request_without_expose_errors
    server = Reclamo::Server.new(expose_errors: false)
    server.expose(Calculator)
    server.use { |_req, _nxt| raise Reclamo::InvalidRequest, "secret details" }

    request = '{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal "Internal server error", response["error"]["data"]
  end
end

class TestArgumentErrorGenericData < Minitest::Test
  def test_argument_error_uses_generic_params_data_when_hidden
    server = Reclamo::Server.new(expose_errors: false)
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
    assert_equal "Invalid method parameters", response["error"]["data"]
  end

  def test_argument_error_exposes_message_when_enabled
    server = Reclamo::Server.new(expose_errors: true)
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_602, response["error"]["code"])
    assert_includes response["error"]["data"], "wrong number of arguments"
  end
end
