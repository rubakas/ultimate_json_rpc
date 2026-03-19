# frozen_string_literal: true

require "test_helper"
require "json"
require "support/discover_helper"
require "reclamo/profiler"
require "reclamo/rate_limit"
require "reclamo/tcp"
require "reclamo/recorder"

class TestHandleRescueScope < Minitest::Test
  def test_handle_returns_parse_error_for_invalid_json
    server = Reclamo::Server.new
    server.expose(Calculator)
    response = JSON.parse(server.handle("not json"))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_handle_does_not_mask_dispatch_errors_as_parse_error
    server = Reclamo::Server.new(expose_errors: true)
    server.expose_method("boom") { raise "handler error" }

    request = '{"jsonrpc":"2.0","method":"boom","id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_603, response["error"]["code"])
    assert_equal "handler error", response["error"]["data"]
  end

  def test_internal_error_not_reported_as_parse_error
    bad_json = Class.new do
      def parse(str) = JSON.parse(str)

      def generate(obj)
        raise "serialize failed" if obj.is_a?(Hash) && obj.key?("result") && obj["result"] == :unserializable

        JSON.generate(obj)
      end
    end.new

    server = Reclamo::Server.new(json: bad_json)
    server.expose_method("bad") { :unserializable }

    request = '{"jsonrpc":"2.0","method":"bad","id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_603, response["error"]["code"])
  end
end

class TestSerializeSingleIdRecovery < Minitest::Test
  def test_error_response_preserves_request_id
    server = Reclamo::Server.new(expose_errors: true)
    server.expose_method("fail") { raise "unexpected" }

    request = { "jsonrpc" => "2.0", "method" => "fail", "id" => 42 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 42, response["id"]
    assert_equal(-32_603, response["error"]["code"])
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

class TestProfilerMaxSamples < Minitest::Test
  def test_durations_capped_at_max_samples
    server = Reclamo::Server.new
    server.expose(Calculator)
    profiler = Reclamo::Profiler.new(server, max_samples: 5)

    10.times do |i|
      request = { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i }
      server.handle(JSON.generate(request))
    end

    stats = profiler["add"]
    assert_equal 10, stats[:count]
    assert_operator stats[:p50], :>, 0
  end

  def test_default_max_samples
    assert_equal 10_000, Reclamo::Profiler::DEFAULT_MAX_SAMPLES
  end
end

class TestRateLimiterEviction < Minitest::Test
  def test_stale_windows_evicted
    limiter = Reclamo::RateLimiter.new(max: 1, period: 0.001, key: ->(req) { req.method_name }) # rubocop:disable Style/SymbolProc

    server = Reclamo::Server.new
    server.expose(Calculator)

    # Create many distinct bucket keys via different methods
    110.times do |i|
      server.expose_method("m#{i}") { i }
    end
    server.use { |req, nxt| limiter.call(req, nxt) }

    110.times do |i|
      request = { "jsonrpc" => "2.0", "method" => "m#{i}", "id" => i }
      server.handle(JSON.generate(request))
    end

    sleep(0.01)

    # One more call should trigger eviction of stale windows
    request = { "jsonrpc" => "2.0", "method" => "m0", "id" => 999 }
    response = JSON.parse(server.handle(JSON.generate(request)))
    assert_equal 0, response["result"]
  end
end

class TestTCPConnectionLimit < Minitest::Test
  def test_default_max_connections
    assert_equal 64, Reclamo::TCP::DEFAULT_MAX_CONNECTIONS
  end
end

class TestRecorderThreadSafety < Minitest::Test
  def test_exchanges_returns_snapshot
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Recorder.new(server)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    snapshot = recorder.exchanges
    assert_equal 1, snapshot.size

    # Mutating snapshot should not affect recorder
    snapshot.clear
    assert_equal 1, recorder.size
  end

  def test_size_is_synchronized
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Recorder.new(server)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert_equal 1, recorder.size
  end
end

class TestRecorderCustomJson < Minitest::Test
  def test_recorder_uses_custom_json_adapter
    output = StringIO.new
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Recorder.new(server, output: output, json: JSON)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert_equal 1, recorder.size
    assert_includes output.string, '"method":"add"'
  end
end

class TestRequestIdFalse < Minitest::Test
  def test_false_id_rejected
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "test", "id" => false })
    end
  end
end

class TestStoreMetadataScalarGuard < Minitest::Test
  def test_expose_with_scalar_deprecated_does_not_crash
    server = Reclamo::Server.new
    server.expose(Calculator, deprecated: true)

    # Should register methods without raising NoMethodError on `true[:method_name]`
    assert server.method?("add")
  end

  def test_expose_with_string_deprecated_does_not_crash
    server = Reclamo::Server.new
    server.expose(Calculator, deprecated: "use v2")

    assert server.method?("add")
  end
end

class TestInvalidRequestFromMiddleware < Minitest::Test
  def test_middleware_raising_invalid_request_returns_invalid_request_code
    server = Reclamo::Server.new(expose_errors: true)
    server.expose(Calculator)
    server.use { |_req, _nxt| raise Reclamo::InvalidRequest, "bad request from middleware" }

    request = '{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal "bad request from middleware", response["error"]["data"]
  end

  def test_middleware_raising_invalid_request_without_expose_errors
    server = Reclamo::Server.new(expose_errors: false)
    server.expose(Calculator)
    server.use { |_req, _nxt| raise Reclamo::InvalidRequest, "secret details" }

    request = '{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}'
    response = JSON.parse(server.handle(request))

    assert_equal(-32_600, response["error"]["code"])
    assert_equal "Internal server error", response["error"]["data"]
  end
end

class TestDocsDiscoverGuard < Minitest::Test
  def test_docs_raises_when_discover_blocked_by_middleware
    require "reclamo/docs"
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use(only: "rpc.discover") { |_req, _nxt| raise Reclamo::InvalidRequest, "blocked" }

    error = assert_raises(RuntimeError) { Reclamo::Docs.new(server).to_markdown }
    assert_match(/rpc\.discover returned an error/, error.message)
  end
end

class TestDangerousMethodsExtended < Minitest::Test
  %w[instance_variable_get instance_variable_set const_get const_set method].each do |dangerous|
    define_method("test_expose_method_#{dangerous}_is_blocked") do
      handler = Reclamo::Handler.new
      assert_raises(ArgumentError) { handler.expose_method(dangerous) { nil } }
    end
  end
end

class TestHandleParsedDoesNotFreezeCaller < Minitest::Test
  def test_handle_parsed_does_not_freeze_callers_method_string
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    method_str = +"ping"
    request = { "jsonrpc" => "2.0", "method" => method_str, "id" => 1 }
    server.handle_parsed(request)

    refute_predicate method_str, :frozen?, "handle_parsed should not freeze caller's method string"
  end

  def test_handle_parsed_does_not_freeze_callers_param_strings
    server = Reclamo::Server.new
    server.expose_method("echo") { |value:| value }

    param_value = +"hello"
    request = { "jsonrpc" => "2.0", "method" => "echo", "params" => { "value" => param_value }, "id" => 1 }
    server.handle_parsed(request)

    refute_predicate param_value, :frozen?, "handle_parsed should not freeze caller's param strings"
  end
end

class TestStoreMetadataSymKeyPriority < Minitest::Test
  include DiscoverHelper

  def test_store_metadata_sym_key_takes_priority
    server = Reclamo::Server.new
    server.expose(Calculator, deprecated: { add: "via sym", "add" => "via str" })
    method_info = discover_methods(server).find { |m| m["name"] == "add" }

    assert_equal "via sym", method_info["deprecated"]
  end
end

class TestBuildResultElseBranch < Minitest::Test
  include DiscoverHelper

  def test_returns_non_hash_non_string_wrapped_in_schema
    server = Reclamo::Server.new
    server.expose_method("tags", returns: [{ "type" => "string" }]) { %w[a b] }
    method_info = discover_methods(server).find { |m| m["name"] == "tags" }

    assert_equal({ "name" => "result", "schema" => [{ "type" => "string" }] }, method_info["result"])
  end
end

class TestDeepDupFrozenKeys < Minitest::Test
  def test_handle_parsed_with_frozen_string_keys
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    # All string keys are already frozen (normal Ruby behavior for string literals)
    request = { "jsonrpc" => "2.0", "method" => "ping", "params" => { "key" => "val" }, "id" => 1 }
    response = JSON.parse(server.handle_parsed(request))

    assert_equal "pong", response["result"]
  end

  def test_handle_parsed_with_symbol_keyed_params
    server = Reclamo::Server.new
    server.expose_method("echo") { |value:| value }

    # Symbol keys in params — deep_dup should handle without crashing
    request = { "jsonrpc" => "2.0", "method" => "echo", "params" => { value: "hello" }, "id" => 1 }
    response = JSON.parse(server.handle_parsed(request))

    assert_equal "hello", response["result"]
  end
end
