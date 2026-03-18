# frozen_string_literal: true

require "test_helper"
require "reclamo/profiler"
require "json"

class TestProfiler < Minitest::Test
  def test_records_method_call
    server, profiler = build_profiled_server
    rpc(server, "add", [2, 3])

    assert_equal 1, profiler["add"][:count]
  end

  def test_tracks_multiple_calls
    server, profiler = build_profiled_server
    3.times { rpc(server, "add", [1, 2]) }

    assert_equal 3, profiler["add"][:count]
  end

  def test_tracks_duration
    server, profiler = build_profiled_server
    rpc(server, "add", [2, 3])
    stats = profiler["add"]

    assert_operator stats[:min], :>, 0
    assert_operator stats[:max], :>=, stats[:min]
    assert_operator stats[:avg], :>, 0
    assert_operator stats[:total], :>, 0
  end

  def test_min_max
    server = Reclamo::Server.new
    server.expose_method("fast") { 1 }
    server.expose_method("slow") do
      sleep(0.05)
      2
    end
    profiler = Reclamo::Profiler.new(server)

    rpc(server, "fast", nil)
    rpc(server, "slow", nil)

    assert_operator profiler["fast"][:max], :<, profiler["slow"][:min]
  end

  def test_percentiles
    server, profiler = build_profiled_server
    10.times { rpc(server, "add", [1, 2]) }
    stats = profiler["add"]

    assert_operator stats[:p50], :>=, stats[:min]
    assert_operator stats[:p95], :>=, stats[:p50]
    assert_operator stats[:p99], :>=, stats[:p95]
    assert_operator stats[:p99], :<=, stats[:max]
  end

  def test_average
    server, profiler = build_profiled_server
    5.times { rpc(server, "add", [1, 2]) }
    stats = profiler["add"]

    expected_avg = stats[:total] / stats[:count]
    assert_in_delta expected_avg, stats[:avg], 0.000001
  end

  def test_separate_methods
    server, profiler = build_profiled_server
    rpc(server, "add", [1, 2])
    rpc(server, "divide", [6, 2])

    assert_equal 1, profiler["add"][:count]
    assert_equal 1, profiler["divide"][:count]
  end

  def test_unknown_method_returns_nil
    _server, profiler = build_profiled_server

    assert_nil profiler["nonexistent"]
  end

  def test_methods_list
    server, profiler = build_profiled_server
    rpc(server, "add", [1, 2])
    rpc(server, "divide", [6, 2])

    assert_equal %w[add divide], profiler.methods
  end

  def test_stats_returns_all
    server, profiler = build_profiled_server
    rpc(server, "add", [1, 2])
    rpc(server, "divide", [6, 2])
    all = profiler.stats

    assert_equal 2, all.size
    assert all.key?("add")
    assert all.key?("divide")
  end

  def test_tracked_methods
    server, profiler = build_profiled_server
    rpc(server, "add", [1, 2])
    rpc(server, "divide", [6, 2])
    assert_equal %w[add divide], profiler.tracked_methods
  end

  def test_reset
    server, profiler = build_profiled_server
    rpc(server, "add", [1, 2])
    profiler.reset

    assert_nil profiler["add"]
    assert_empty profiler.methods
  end

  def test_records_errors_too
    server, profiler = build_profiled_server
    rpc(server, "nonexistent", nil)

    assert_equal 1, profiler["nonexistent"][:count]
  end

  def test_thread_safe_with_concurrent_batches
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    profiler = Reclamo::Profiler.new(server)

    batch = 10.times.map { |i| { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i } }
    server.handle(JSON.generate(batch))

    assert_equal 10, profiler["add"][:count]
  end

  private

  def build_profiled_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    profiler = Reclamo::Profiler.new(server)
    [server, profiler]
  end

  def rpc(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    server.handle(JSON.generate(request))
  end
end
