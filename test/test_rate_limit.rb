# frozen_string_literal: true

require "test_helper"
require "reclamo/rate_limit"
require "json"

class TestRateLimit < Minitest::Test
  def test_allows_requests_within_limit
    server = build_server(max: 3, period: 60)
    3.times do |i|
      response = call(server, "add", [i, 1])
      assert response.key?("result"), "Request #{i + 1} should succeed"
    end
  end

  def test_blocks_when_limit_exceeded
    server = build_server(max: 2, period: 60)
    call(server, "add", [1, 2])
    call(server, "add", [3, 4])
    response = call(server, "add", [5, 6])

    assert_equal 429, response["error"]["code"]
    assert_equal "Rate limit exceeded", response["error"]["message"]
  end

  def test_window_slides_after_period
    server = build_server(max: 1, period: 0.05)
    call(server, "add", [1, 2])
    sleep(0.12)
    response = call(server, "add", [3, 4])

    assert response.key?("result"), "Request should succeed after window expires"
  end

  def test_per_caller_with_symbol_key
    user = "alice"
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |req, nxt| req.context[:user] = user; nxt.call } # rubocop:disable Style/Semicolon
    server.rate_limit(max: 1, period: 60, key: :user)

    assert call(server, "add", [1, 2]).key?("result")
    assert_equal 429, call(server, "add", [3, 4])["error"]["code"]

    # Different user is allowed
    user = "bob"
    assert call(server, "add", [5, 6]).key?("result")
  end

  def test_per_caller_with_proc_key
    api_key = "key-a"
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |req, nxt| req.context[:api_key] = api_key; nxt.call } # rubocop:disable Style/Semicolon
    server.rate_limit(max: 1, period: 60, key: ->(req) { req.context[:api_key] })

    assert call(server, "add", [1, 2]).key?("result")
    assert_equal 429, call(server, "add", [3, 4])["error"]["code"]
  end

  def test_scoped_with_only
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.rate_limit(max: 1, period: 60, only: ["add"])

    call(server, "add", [1, 2])
    blocked = call(server, "add", [3, 4])
    allowed = call(server, "divide", [6, 2])

    assert_equal 429, blocked["error"]["code"]
    assert allowed.key?("result"), "divide should not be rate-limited"
  end

  def test_scoped_with_except
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.rate_limit(max: 1, period: 60, except: ["divide"])

    call(server, "add", [1, 2])
    blocked = call(server, "add", [3, 4])
    allowed = call(server, "divide", [6, 2])

    assert_equal 429, blocked["error"]["code"]
    assert allowed.key?("result")
  end

  def test_falsy_context_value_used_as_key
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |req, nxt| req.context[:uid] = 0; nxt.call } # rubocop:disable Style/Semicolon
    server.rate_limit(max: 1, period: 60, key: :uid)

    r1 = call(server, "add", [1, 2])
    r2 = call(server, "add", [3, 4])
    assert r1.key?("result"), "First call should succeed"
    assert_equal 429, r2["error"]["code"], "Second call should be rate-limited under key 0, not :unknown"
  end

  def test_custom_error_code_and_message
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.rate_limit(max: 1, period: 60, code: 1429, message: "Slow down")

    call(server, "add", [1, 2])
    response = call(server, "add", [3, 4])

    assert_equal 1429, response["error"]["code"]
    assert_equal "Slow down", response["error"]["message"]
  end

  def test_chainable
    server = Reclamo::Server.new
    result = server.rate_limit(max: 10, period: 60)

    assert_equal server, result
  end

  def test_thread_safe
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    server.rate_limit(max: 5, period: 60)

    batch = 10.times.map { |i| { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i } }
    responses = JSON.parse(server.handle(JSON.generate(batch)))

    successes = responses.count { |r| r.key?("result") }
    errors = responses.count { |r| r.key?("error") }

    assert_equal 5, successes
    assert_equal 5, errors
  end

  private

  def build_server(max:, period:)
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.rate_limit(max:, period:)
    server
  end

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end
end
