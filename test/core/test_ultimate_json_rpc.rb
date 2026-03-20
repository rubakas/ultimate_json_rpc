# frozen_string_literal: true

require "test_helper"

class TestUltimateJsonRpc < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::UltimateJsonRpc::VERSION
  end

  def test_error_code_constants
    assert_equal(-32_700, UltimateJsonRpc::Core::PARSE_ERROR)
    assert_equal(-32_600, UltimateJsonRpc::Core::INVALID_REQUEST)
    assert_equal(-32_601, UltimateJsonRpc::Core::METHOD_NOT_FOUND)
    assert_equal(-32_602, UltimateJsonRpc::Core::INVALID_PARAMS)
    assert_equal(-32_603, UltimateJsonRpc::Core::INTERNAL_ERROR)
  end

  def test_server_error_range_constants
    assert_equal(-32_099, UltimateJsonRpc::Core::SERVER_ERROR_MIN)
    assert_equal(-32_000, UltimateJsonRpc::Core::SERVER_ERROR_MAX)
    assert_operator UltimateJsonRpc::Core::SERVER_ERROR_MIN, :<, UltimateJsonRpc::Core::SERVER_ERROR_MAX
  end

  def test_reserved_error_range_constants
    assert_equal(-32_768, UltimateJsonRpc::Core::RESERVED_ERROR_MIN)
    assert_equal(-32_000, UltimateJsonRpc::Core::RESERVED_ERROR_MAX)
  end

  def test_error_class_hierarchy
    assert_operator UltimateJsonRpc::Core::InvalidRequest, :<, UltimateJsonRpc::Core::Error
    assert_operator UltimateJsonRpc::Core::InvalidParams, :<, UltimateJsonRpc::Core::Error
    assert_operator UltimateJsonRpc::Core::MethodNotFound, :<, UltimateJsonRpc::Core::Error
    assert_operator UltimateJsonRpc::Core::ApplicationError, :<, UltimateJsonRpc::Core::Error
    assert_operator UltimateJsonRpc::Core::ServerError, :<, UltimateJsonRpc::Core::Error
    assert_operator UltimateJsonRpc::Core::Error, :<, StandardError
  end
end
