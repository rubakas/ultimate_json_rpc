# frozen_string_literal: true

require "test_helper"
require "json"

class TestErrorCatalog < Minitest::Test
  def test_register_error_returns_self
    server = Reclamo::Server.new

    assert_equal server, server.register_error(42, "CustomError")
  end

  def test_register_error_appears_in_discover
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(42, "InsufficientFunds", "Account balance too low")
    result = discover(server)
    errors = result["components"]["errors"]

    assert_equal 1, errors.size
    assert_equal 42, errors[0]["code"]
    assert_equal "InsufficientFunds", errors[0]["message"]
    assert_equal "Account balance too low", errors[0]["data"]
  end

  def test_register_error_without_description
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(43, "AccountLocked")
    errors = discover(server)["components"]["errors"]

    assert_equal 43, errors[0]["code"]
    assert_equal "AccountLocked", errors[0]["message"]
    refute errors[0].key?("data")
  end

  def test_multiple_errors
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(42, "InsufficientFunds")
    server.register_error(43, "AccountLocked")
    errors = discover(server)["components"]["errors"]

    assert_equal 2, errors.size
    assert_equal([42, 43], errors.map { |e| e["code"] })
  end

  def test_no_errors_omits_components
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    refute discover(server).key?("components")
  end

  def test_duplicate_code_raises
    server = Reclamo::Server.new
    server.register_error(42, "Error1")

    assert_raises(ArgumentError) { server.register_error(42, "Error2") }
  end

  def test_non_integer_code_raises
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.register_error("42", "Error") }
  end

  def test_chainable
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    result = server
             .register_error(1, "One")
             .register_error(2, "Two")
    errors = discover(result)["components"]["errors"]

    assert_equal 2, errors.size
  end

  def test_survives_freeze
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(42, "Frozen")
    server.freeze
    errors = discover(server)["components"]["errors"]

    assert_equal 42, errors[0]["code"]
  end

  def test_frozen_server_rejects_register
    server = Reclamo::Server.new
    server.freeze

    assert_raises(FrozenError) { server.register_error(42, "Late") }
  end

  def test_reserved_json_rpc_code_raises
    server = Reclamo::Server.new
    err = assert_raises(ArgumentError) { server.register_error(-32_700, "Parse error") }
    assert_match(/reserved/, err.message)
  end

  def test_reserved_boundary_code_raises
    server = Reclamo::Server.new
    assert_raises(ArgumentError) { server.register_error(-32_000, "Boundary") }
    assert_raises(ArgumentError) { server.register_error(-32_768, "Boundary") }
  end

  def test_negative_error_codes
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(-100, "CustomServerError")
    errors = discover(server)["components"]["errors"]

    assert_equal(-100, errors[0]["code"])
  end

  private

  def discover(server)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))["result"]
  end
end
