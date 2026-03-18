# frozen_string_literal: true

require "test_helper"

class TestReclamo < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Reclamo::VERSION
  end

  def test_error_code_constants
    assert_equal(-32_700, Reclamo::PARSE_ERROR)
    assert_equal(-32_600, Reclamo::INVALID_REQUEST)
    assert_equal(-32_601, Reclamo::METHOD_NOT_FOUND)
    assert_equal(-32_602, Reclamo::INVALID_PARAMS)
    assert_equal(-32_603, Reclamo::INTERNAL_ERROR)
  end

  def test_server_error_range_constants
    assert_equal(-32_099, Reclamo::SERVER_ERROR_MIN)
    assert_equal(-32_000, Reclamo::SERVER_ERROR_MAX)
    assert Reclamo::SERVER_ERROR_MIN < Reclamo::SERVER_ERROR_MAX
  end

  def test_reserved_error_range_constants
    assert_equal(-32_768, Reclamo::RESERVED_ERROR_MIN)
    assert_equal(-32_000, Reclamo::RESERVED_ERROR_MAX)
  end
end
