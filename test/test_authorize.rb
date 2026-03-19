# frozen_string_literal: true

require "test_helper"
require "json"

class TestAuthorize < Minitest::Test
  def test_authorized_request_succeeds
    server = build_server
    server.authorize("add") { |_req| true }
    response = call(server, "add", [2, 3])

    assert_equal 5, response["result"]
  end

  def test_denied_request_returns_error
    server = build_server
    server.authorize("add") { |_req| false }
    response = call(server, "add", [2, 3])

    assert_equal 403, response["error"]["code"]
    assert_equal "Forbidden", response["error"]["message"]
  end

  def test_denied_returns_nil_check
    server = build_server
    server.authorize("add") { |_req| nil }
    response = call(server, "add", [2, 3])

    assert_equal 403, response["error"]["code"]
  end

  def test_pattern_matching_applies_only_to_matched
    server = build_server
    server.authorize("add") { |_req| false }
    response = call(server, "divide", [6, 2])

    assert_equal 3.0, response["result"]
  end

  def test_glob_pattern
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math")
    server.authorize("math.*") { |req| req.context[:admin] }
    response = call(server, "math.add", [1, 2])

    assert_equal 403, response["error"]["code"]
  end

  def test_glob_pattern_allows_with_context
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math")
    server.authorize("math.*") do |req|
      req.context[:admin] = true # set by earlier middleware in real use
      true
    end
    response = call(server, "math.add", [1, 2])

    assert_equal 3, response["result"]
  end

  def test_global_authorization_no_patterns
    server = build_server
    server.authorize { |_req| false }
    response = call(server, "add", [2, 3])

    assert_equal 403, response["error"]["code"]
  end

  def test_custom_error_code
    server = build_server
    server.authorize("add", code: 1001, message: "Unauthorized") { |_req| false }
    response = call(server, "add", [2, 3])

    assert_equal 1001, response["error"]["code"]
    assert_equal "Unauthorized", response["error"]["message"]
  end

  def test_multiple_authorize_calls
    server = build_server
    server.authorize("add") { |_req| true }
    server.authorize("divide") { |_req| false }

    assert_equal 5, call(server, "add", [2, 3])["result"]
    assert_equal 403, call(server, "divide", [6, 2])["error"]["code"]
  end

  def test_authorization_with_context
    server = build_server
    server.use { |req, nxt| req.context[:role] = :admin; nxt.call } # rubocop:disable Style/Semicolon
    server.authorize("add") { |req| req.context[:role] == :admin }
    response = call(server, "add", [2, 3])

    assert_equal 5, response["result"]
  end

  def test_chainable
    server = Reclamo::Server.new
    result = server.authorize { |_req| true }

    assert_equal server, result
  end

  def test_requires_block
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.authorize("add") }
  end

  def test_rejects_reserved_code_at_setup
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.authorize(code: -32_000) { |_req| false } }
  end

  def test_rejects_non_integer_code_at_setup
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.authorize(code: "403") { |_req| false } }
  end

  def test_multiple_patterns
    server = build_server
    server.authorize("add", "divide") { |_req| false }

    assert_equal 403, call(server, "add", [2, 3])["error"]["code"]
    assert_equal 403, call(server, "divide", [6, 2])["error"]["code"]
  end

  private

  def build_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    server
  end

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end
end
