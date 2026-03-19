# frozen_string_literal: true

require "test_helper"
require "json"

class TestConcurrentBatch < Minitest::Test
  def test_concurrent_batch_returns_correct_results
    server = build_server(concurrent_batches: true)
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [5, 6], "id" => 3 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 3, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
    assert_equal 11, responses[2]["result"]
  end

  def test_concurrent_batch_preserves_order
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose_method("slow") do |n|
      sleep(0.01 * n)
      n
    end
    requests = [
      { "jsonrpc" => "2.0", "method" => "slow", "params" => [3], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "slow", "params" => [1], "id" => 2 },
      { "jsonrpc" => "2.0", "method" => "slow", "params" => [2], "id" => 3 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal([1, 2, 3], responses.map { |r| r["id"] })
    assert_equal([3, 1, 2], responses.map { |r| r["result"] })
  end

  def test_concurrent_batch_actually_runs_concurrently
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose_method("sleep_then") do |ms|
      sleep(ms / 1000.0)
      ms
    end
    requests = 5.times.map do |i|
      { "jsonrpc" => "2.0", "method" => "sleep_then", "params" => [50], "id" => i }
    end

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    responses = JSON.parse(server.handle(JSON.generate(requests)))
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    assert_equal 5, responses.size
    # 5 items at 50ms each should take ~50ms concurrent, not ~250ms sequential
    assert_operator elapsed, :<, 0.3, "Expected concurrent execution to be faster than sequential"
  end

  def test_concurrent_batch_handles_notifications
    server = build_server(concurrent_batches: true)
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 1, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_concurrent_batch_all_notifications
    server = build_server(concurrent_batches: true)
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4] }
    ]

    assert_nil server.handle(JSON.generate(requests))
  end

  def test_concurrent_batch_handles_errors
    server = build_server(concurrent_batches: true)
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "nonexistent", "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 3, responses[0]["result"]
    assert_equal(-32_601, responses[1]["error"]["code"])
  end

  def test_concurrent_batch_respects_max_batch_size
    server = Reclamo::Server.new(concurrent_batches: true, max_batch_size: 2)
    server.expose(Calculator)
    requests = 3.times.map { |i| { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i } }
    response = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal "Batch too large", response["error"]["message"]
  end

  def test_concurrent_batch_with_timeout
    server = Reclamo::Server.new(concurrent_batches: true, timeout: 0.05)
    server.expose_method("fast") { "ok" }
    server.expose_method("slow") do
      sleep(1)
      "done"
    end
    requests = [
      { "jsonrpc" => "2.0", "method" => "fast", "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "slow", "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal "ok", responses[0]["result"]
    assert_equal(-32_001, responses[1]["error"]["code"])
  end

  def test_concurrent_batch_with_invalid_items
    server = build_server(concurrent_batches: true)
    requests = [
      1,
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal(-32_600, responses[0]["error"]["code"])
    assert_equal 3, responses[1]["result"]
  end

  def test_concurrent_batch_empty_returns_error
    server = build_server(concurrent_batches: true)
    response = JSON.parse(server.handle("[]"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_default_is_sequential
    server = Reclamo::Server.new

    refute server.concurrent_batches?
  end

  def test_concurrent_batches_predicate
    server = Reclamo::Server.new(concurrent_batches: true)

    assert server.concurrent_batches?
  end

  def test_concurrent_batch_error_preserves_id
    server = Reclamo::Server.new(concurrent_batches: true)
    circ = {}
    circ["self"] = circ
    server.expose_method("bad") { circ }
    server.expose_method("ok") { "fine" }
    requests = [
      { "jsonrpc" => "2.0", "method" => "bad", "id" => 42 },
      { "jsonrpc" => "2.0", "method" => "ok", "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    bad_resp = responses.find { |r| r["id"] == 42 }
    assert_equal(-32_603, bad_resp["error"]["code"])
    assert_equal 42, bad_resp["id"]
  end

  def test_concurrent_batch_with_middleware
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    calls = Queue.new # thread-safe
    server.use do |req, nxt|
      calls << req.method_name
      nxt.call
    end
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal 2, calls.size
  end

  def test_concurrent_batch_with_hooks
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    methods = Queue.new # thread-safe
    server.on(:request) { |req| methods << req.method_name }
    requests = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 2, responses.size
    assert_equal 2, methods.size
  end

  private

  def build_server(concurrent_batches: false)
    server = Reclamo::Server.new(concurrent_batches:)
    server.expose(Calculator)
    server
  end
end

class TestConcurrentBatchSafety < Minitest::Test
  def test_thread_exception_does_not_corrupt_batch
    bad_json = Class.new do
      def parse(str) = JSON.parse(str)

      def generate(obj)
        raise "serialize boom" if obj.is_a?(Hash) && obj.key?("result") && obj["result"] == :boom

        JSON.generate(obj)
      end
    end.new

    server = Reclamo::Server.new(concurrent_batches: true, json: bad_json)
    server.expose_method("boom") { :boom }
    server.expose_method("ok") { "ok" }

    requests = [
      { "jsonrpc" => "2.0", "method" => "ok", "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "boom", "id" => 2 },
      { "jsonrpc" => "2.0", "method" => "ok", "id" => 3 }
    ]
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 3, responses.size
    assert_equal "ok", responses[0]["result"]
    assert_equal(-32_603, responses[1]["error"]["code"])
    assert_equal "ok", responses[2]["result"]
  end

  def test_max_concurrency_limits_threads
    server = Reclamo::Server.new(concurrent_batches: true, max_concurrency: 2)
    thread_ids = Queue.new
    server.expose_method("track") do
      thread_ids << Thread.current.object_id
      sleep(0.01)
      "ok"
    end

    requests = 4.times.map { |i| { "jsonrpc" => "2.0", "method" => "track", "id" => i } }
    responses = JSON.parse(server.handle(JSON.generate(requests)))

    assert_equal 4, responses.size
    unique_threads = thread_ids.size.times.map { thread_ids.pop }.uniq
    assert_operator unique_threads.size, :<=, 2
  end
end
