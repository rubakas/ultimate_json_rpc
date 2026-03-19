# frozen_string_literal: true

require "test_helper"
require "reclamo/extras/recorder"
require "json"
require "stringio"

class TestRecorder < Minitest::Test
  def test_records_successful_exchange
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_equal 1, recorder.size
    assert_equal "add", recorder.exchanges[0]["method"]
    assert_equal [2, 3], recorder.exchanges[0]["params"]
    assert_equal 5, recorder.exchanges[0]["result"]
  end

  def test_records_duration
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_kind_of Float, recorder.exchanges[0]["duration"]
    assert_operator recorder.exchanges[0]["duration"], :>=, 0
  end

  def test_records_error_exchange
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"nonexistent","id":1}')

    assert_equal 1, recorder.size
    assert_equal "nonexistent", recorder.exchanges[0]["method"]
    assert_equal "Reclamo::Core::MethodNotFound", recorder.exchanges[0]["error"]["class"]
    refute recorder.exchanges[0].key?("result")
  end

  def test_records_notifications
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2]}')

    assert_equal 1, recorder.size
    assert_equal "add", recorder.exchanges[0]["method"]
  end

  def test_records_failed_notification
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"nonexistent"}')

    assert_equal 1, recorder.size
    exchange = recorder.exchanges[0]
    assert_equal "nonexistent", exchange["method"]
    assert exchange.key?("error")
    assert_equal "Reclamo::Core::MethodNotFound", exchange["error"]["class"]
  end

  def test_records_multiple_exchanges
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    server.handle('{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}')

    assert_equal 2, recorder.size
  end

  def test_records_batch_exchanges
    server, recorder = build_recorded_server
    batch = '[{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1},' \
            '{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}]'
    server.handle(batch)

    assert_equal 2, recorder.size
  end

  def test_clear
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    recorder.clear

    assert_equal 0, recorder.size
    assert_empty recorder.exchanges
  end

  def test_output_to_io
    output = StringIO.new
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Extras::Recorder.new(server, output:)
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    line = JSON.parse(output.string.strip)
    assert_equal "add", line["method"]
    assert_equal 5, line["result"]
  end

  def test_output_writes_jsonl
    output = StringIO.new
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Extras::Recorder.new(server, output:)
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    server.handle('{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}')

    lines = output.string.strip.split("\n")
    assert_equal 2, lines.size
    assert_equal [1, 2], JSON.parse(lines[0])["params"]
    assert_equal [3, 4], JSON.parse(lines[1])["params"]
  end

  def test_thread_safe_with_concurrent_batches
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)
    batch = 10.times.map { |i| { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i } }
    server.handle(JSON.generate(batch))

    assert_equal 10, recorder.size
  end

  def test_no_result_key_on_error
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"nonexistent","id":1}')

    refute recorder.exchanges[0].key?("result")
    assert recorder.exchanges[0].key?("error")
  end

  def test_no_error_key_on_success
    server, recorder = build_recorded_server
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert recorder.exchanges[0].key?("result")
    refute recorder.exchanges[0].key?("error")
  end

  def test_records_false_result
    server = Reclamo::Server.new
    server.expose_method("falsy") { false }
    recorder = Reclamo::Extras::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"falsy","id":1}')

    assert_equal false, recorder.exchanges[0]["result"]
  end

  def test_records_zero_result
    server = Reclamo::Server.new
    server.expose_method("zero") { 0 }
    recorder = Reclamo::Extras::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"zero","id":1}')

    assert_equal 0, recorder.exchanges[0]["result"]
  end

  def test_records_empty_string_result
    server = Reclamo::Server.new
    server.expose_method("empty") { "" }
    recorder = Reclamo::Extras::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"empty","id":1}')

    assert_equal "", recorder.exchanges[0]["result"]
  end

  def test_records_nil_result
    server = Reclamo::Server.new
    server.expose_method("nil_method") { nil }
    recorder = Reclamo::Extras::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"nil_method","id":1}')

    assert recorder.exchanges[0].key?("result")
    assert_nil recorder.exchanges[0]["result"]
  end

  def test_keyword_params_recorded
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    recorder = Reclamo::Extras::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"greet","params":{"name":"Alice"},"id":1}')

    assert_equal({ "name" => "Alice" }, recorder.exchanges[0]["params"])
  end

  private

  def build_recorded_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)
    [server, recorder]
  end
end

class TestRecorderMaxExchanges < Minitest::Test
  def test_exchanges_capped_at_max
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server, max_exchanges: 3)

    5.times do |i|
      server.handle("{\"jsonrpc\":\"2.0\",\"method\":\"add\",\"params\":[#{i},1],\"id\":#{i}}")
    end

    assert_equal 3, recorder.size
    # Should retain the most recent entries (oldest shifted out)
    methods = recorder.exchanges.map { |e| e["params"][0] }
    assert_equal [2, 3, 4], methods
  end

  def test_nil_max_exchanges_means_unbounded
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)

    5.times do |i|
      server.handle("{\"jsonrpc\":\"2.0\",\"method\":\"add\",\"params\":[#{i},1],\"id\":#{i}}")
    end

    assert_equal 5, recorder.size
  end
end

class TestRecorderIOErrors < Minitest::Test
  def test_io_error_does_not_deadlock
    broken_io = Object.new
    def broken_io.puts(*)
      raise Errno::EPIPE
    end

    def broken_io.flush; end

    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server, output: broken_io)

    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    server.handle('{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}')

    assert_equal 2, recorder.size
  end
end

class TestRecorderParseError < Minitest::Test
  def test_parse_error_not_recorded
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)

    server.handle("not json")

    assert_equal 0, recorder.size
  end
end

class TestRecorderThreadSafety < Minitest::Test
  def test_exchanges_returns_snapshot
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    snapshot = recorder.exchanges
    assert_equal 1, snapshot.size

    snapshot.clear
    assert_equal 1, recorder.size
  end

  def test_size_is_synchronized
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Extras::Recorder.new(server)

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
    recorder = Reclamo::Extras::Recorder.new(server, output: output, json: JSON)

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    server.handle(JSON.generate(request))

    assert_equal 1, recorder.size
    assert_includes output.string, '"method":"add"'
  end
end

class TestRecorderConcurrentOutput < Minitest::Test
  def test_concurrent_output_produces_valid_jsonl
    output = StringIO.new
    server = Reclamo::Server.new(concurrent_batches: true)
    server.expose(Calculator)
    Reclamo::Extras::Recorder.new(server, output: output)

    requests = 10.times.map { |i| { "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i } }
    server.handle(JSON.generate(requests))

    lines = output.string.split("\n").reject(&:empty?)
    assert_equal 10, lines.size
    lines.each { |line| assert JSON.parse(line), "Each line must be valid JSON" }
  end
end
