# frozen_string_literal: true

require "test_helper"
require "support/discover_helper"
require "json"

class TestErrorCatalog < Minitest::Test
  include DiscoverHelper

  def test_register_error_returns_self
    server = UltimateJsonRpc::Server.new

    assert_equal server, server.register_error(code: 42, message: "CustomError")
  end

  def test_register_error_appears_in_discover
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 42, message: "InsufficientFunds", description: "Account balance too low")
    result = discover_result(server)
    errors = result["components"]["errors"]

    assert_equal 1, errors.size
    assert_equal 42, errors[0]["code"]
    assert_equal "InsufficientFunds", errors[0]["message"]
    assert_equal "Account balance too low", errors[0]["data"]
  end

  def test_register_error_without_description
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 43, message: "AccountLocked")
    errors = discover_result(server)["components"]["errors"]

    assert_equal 43, errors[0]["code"]
    assert_equal "AccountLocked", errors[0]["message"]
    refute errors[0].key?("data")
  end

  def test_multiple_errors
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 42, message: "InsufficientFunds")
    server.register_error(code: 43, message: "AccountLocked")
    errors = discover_result(server)["components"]["errors"]

    assert_equal 2, errors.size
    assert_equal([42, 43], errors.map { |e| e["code"] })
  end

  def test_no_errors_omits_components
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_result(server).key?("components")
  end

  def test_duplicate_code_raises
    server = UltimateJsonRpc::Server.new
    server.register_error(code: 42, message: "Error1")

    assert_raises(ArgumentError) { server.register_error(code: 42, message: "Error2") }
  end

  def test_non_integer_code_raises
    server = UltimateJsonRpc::Server.new

    assert_raises(ArgumentError) { server.register_error(code: "42", message: "Error") }
  end

  def test_chainable
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    result = server
             .register_error(code: 1, message: "One")
             .register_error(code: 2, message: "Two")
    errors = discover_result(result)["components"]["errors"]

    assert_equal 2, errors.size
  end

  def test_survives_freeze
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 42, message: "Frozen")
    server.freeze
    errors = discover_result(server)["components"]["errors"]

    assert_equal 42, errors[0]["code"]
  end

  def test_frozen_server_rejects_register
    server = UltimateJsonRpc::Server.new
    server.freeze

    assert_raises(FrozenError) { server.register_error(code: 42, message: "Late") }
  end

  def test_reserved_json_rpc_code_raises
    server = UltimateJsonRpc::Server.new
    err = assert_raises(ArgumentError) { server.register_error(code: -32_700, message: "Parse error") }
    assert_match(/reserved/, err.message)
  end

  def test_reserved_boundary_code_raises
    server = UltimateJsonRpc::Server.new
    assert_raises(ArgumentError) { server.register_error(code: -32_000, message: "Boundary") }
    assert_raises(ArgumentError) { server.register_error(code: -32_768, message: "Boundary") }
  end

  def test_negative_error_codes
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: -100, message: "CustomServerError")
    errors = discover_result(server)["components"]["errors"]

    assert_equal(-100, errors[0]["code"])
  end
end
