# frozen_string_literal: true

require "test_helper"

class TestResponseSuccess < Minitest::Test
  def test_success_structure
    response = Reclamo::Core::Response.success("ok", 1)

    assert_equal "2.0", response["jsonrpc"]
    assert_equal "ok", response["result"]
    assert_equal 1, response["id"]
    refute response.key?("error")
  end

  def test_success_with_nil_result
    response = Reclamo::Core::Response.success(nil, 1)

    assert_nil response["result"]
    assert response.key?("result")
  end

  def test_success_with_false_result
    response = Reclamo::Core::Response.success(false, 1)

    assert_equal false, response["result"]
  end

  def test_success_with_null_id
    response = Reclamo::Core::Response.success("ok", nil)

    assert_nil response["id"]
  end
end

class TestResponseError < Minitest::Test
  def test_error_structure
    response = Reclamo::Core::Response.error(Reclamo::Core::METHOD_NOT_FOUND, 1)

    assert_equal "2.0", response["jsonrpc"]
    assert_equal(-32_601, response["error"]["code"])
    assert_equal "Method not found", response["error"]["message"]
    assert_equal 1, response["id"]
    refute response.key?("result")
  end

  def test_error_with_custom_message
    response = Reclamo::Core::Response.error(Reclamo::Core::INTERNAL_ERROR, 1, message: "custom")

    assert_equal "custom", response["error"]["message"]
  end

  def test_error_with_data
    response = Reclamo::Core::Response.error(Reclamo::Core::INTERNAL_ERROR, 1, data: "details")

    assert_equal "details", response["error"]["data"]
  end

  def test_error_without_data_omits_key
    response = Reclamo::Core::Response.error(Reclamo::Core::INTERNAL_ERROR, 1)

    refute response["error"].key?("data")
  end

  def test_error_with_false_data_includes_key
    response = Reclamo::Core::Response.error(Reclamo::Core::INTERNAL_ERROR, 1, data: false)

    assert_equal false, response["error"]["data"]
  end

  def test_error_with_zero_data_includes_key
    response = Reclamo::Core::Response.error(Reclamo::Core::INTERNAL_ERROR, 1, data: 0)

    assert_equal 0, response["error"]["data"]
  end

  def test_error_with_null_id
    response = Reclamo::Core::Response.error(Reclamo::Core::PARSE_ERROR, nil)

    assert_nil response["id"]
  end

  def test_error_uses_default_message_from_code
    response = Reclamo::Core::Response.error(Reclamo::Core::PARSE_ERROR, nil)

    assert_equal "Parse error", response["error"]["message"]
  end

  def test_error_unknown_code_uses_fallback_message
    response = Reclamo::Core::Response.error(999, 1)

    assert_equal "Unknown error", response["error"]["message"]
  end
end
