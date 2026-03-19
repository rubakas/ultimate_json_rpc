# frozen_string_literal: true

require "test_helper"

class TestReclamo < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Reclamo::VERSION
  end

  def test_error_code_constants
    assert_equal(-32_700, Reclamo::Core::PARSE_ERROR)
    assert_equal(-32_600, Reclamo::Core::INVALID_REQUEST)
    assert_equal(-32_601, Reclamo::Core::METHOD_NOT_FOUND)
    assert_equal(-32_602, Reclamo::Core::INVALID_PARAMS)
    assert_equal(-32_603, Reclamo::Core::INTERNAL_ERROR)
  end

  def test_server_error_range_constants
    assert_equal(-32_099, Reclamo::Core::SERVER_ERROR_MIN)
    assert_equal(-32_000, Reclamo::Core::SERVER_ERROR_MAX)
    assert Reclamo::Core::SERVER_ERROR_MIN < Reclamo::Core::SERVER_ERROR_MAX
  end

  def test_reserved_error_range_constants
    assert_equal(-32_768, Reclamo::Core::RESERVED_ERROR_MIN)
    assert_equal(-32_000, Reclamo::Core::RESERVED_ERROR_MAX)
  end

  def test_error_class_hierarchy
    assert_operator Reclamo::Core::InvalidRequest, :<, Reclamo::Core::Error
    assert_operator Reclamo::Core::InvalidParams, :<, Reclamo::Core::Error
    assert_operator Reclamo::Core::MethodNotFound, :<, Reclamo::Core::Error
    assert_operator Reclamo::Core::ApplicationError, :<, Reclamo::Core::Error
    assert_operator Reclamo::Core::ServerError, :<, Reclamo::Core::Error
    assert_operator Reclamo::Core::Error, :<, StandardError
  end
end
