# frozen_string_literal: true

require "test_helper"
require "json"

class TestServerBatch < Minitest::Test
  def setup
    @server = UltimateJsonRpc::Server.new
    @server.expose(Calculator)
  end

  def test_batch_request
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_batch_with_notification
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 1, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_empty_batch
    response = JSON.parse(@server.handle("[]"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_batch_all_notifications
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    ]

    assert_nil @server.handle(JSON.generate(requests))
  end

  def test_batch_with_discover
    requests = [
      { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 2 }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert responses[0]["result"].key?("methods")
    assert_equal 3, responses[1]["result"]
  end

  def test_batch_with_invalid_items
    requests = [
      1,
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    ]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal(-32_600, responses[0]["error"]["code"])
    assert_equal 3, responses[1]["result"]
  end

  def test_batch_non_serializable_does_not_break_other_responses
    responses = batch_with_bad_and_good_responses

    assert_equal 2, responses.size
    assert_equal(-32_603, responses[0]["error"]["code"])
    assert_equal 5, responses[1]["result"]
  end

  def test_batch_non_serializable_preserves_ids
    responses = batch_with_bad_and_good_responses

    assert_equal 1, responses[0]["id"]
    assert_equal 2, responses[1]["id"]
  end

  def test_batch_all_invalid_items
    requests = [1, "string", true]
    responses = JSON.parse(@server.handle(JSON.generate(requests)))

    assert_equal 3, responses.size
    responses.each do |resp|
      assert_equal(-32_600, resp["error"]["code"])
      assert_nil resp["id"]
    end
  end

  def test_batch_single_notification
    requests = [{ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }]

    assert_nil @server.handle(JSON.generate(requests))
  end

  def test_batch_multiple_notifications
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [5, 6] }
    ]

    assert_nil @server.handle(JSON.generate(requests))
  end

  private

  def batch_with_bad_and_good_responses
    server = UltimateJsonRpc::Server.new
    circ = {}
    circ["self"] = circ
    server.expose_method("bad") { circ }
    server.expose(Calculator)

    requests = [
      { "jsonrpc" => "2.0", "method" => "bad", "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 2 }
    ]
    JSON.parse(server.handle(JSON.generate(requests)))
  end
end

class TestServerBatchSizeLimit < Minitest::Test
  def test_batch_within_limit_succeeds
    server = UltimateJsonRpc::Server.new(max_batch_size: 2)
    server.expose(Calculator)

    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
  end

  def test_batch_exceeding_limit_returns_error
    server = UltimateJsonRpc::Server.new(max_batch_size: 2)
    server.expose(Calculator)

    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [5, 6], "id" => 3 }
    ]
    response = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal "Invalid Request", response["error"]["message"]
    assert_equal "Batch too large", response["error"]["data"]
  end

  def test_default_max_batch_size
    server = UltimateJsonRpc::Server.new

    assert_equal 100, server.max_batch_size
  end

  def test_nil_disables_batch_limit
    server = UltimateJsonRpc::Server.new(max_batch_size: nil)
    server.expose(Calculator)

    requests = 150.times.map do |i|
      { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i }
    end
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 150, responses.size
  end
end
