# frozen_string_literal: true

require "test_helper"
require "reclamo/recorder"
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
    assert_equal "Reclamo::MethodNotFound", recorder.exchanges[0]["error"]["class"]
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
    assert_equal "Reclamo::MethodNotFound", exchange["error"]["class"]
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
    Reclamo::Recorder.new(server, output:)
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    line = JSON.parse(output.string.strip)
    assert_equal "add", line["method"]
    assert_equal 5, line["result"]
  end

  def test_output_writes_jsonl
    output = StringIO.new
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Recorder.new(server, output:)
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
    recorder = Reclamo::Recorder.new(server)
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
    recorder = Reclamo::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"falsy","id":1}')

    assert_equal false, recorder.exchanges[0]["result"]
  end

  def test_records_zero_result
    server = Reclamo::Server.new
    server.expose_method("zero") { 0 }
    recorder = Reclamo::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"zero","id":1}')

    assert_equal 0, recorder.exchanges[0]["result"]
  end

  def test_records_empty_string_result
    server = Reclamo::Server.new
    server.expose_method("empty") { "" }
    recorder = Reclamo::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"empty","id":1}')

    assert_equal "", recorder.exchanges[0]["result"]
  end

  def test_records_nil_result
    server = Reclamo::Server.new
    server.expose_method("nil_method") { nil }
    recorder = Reclamo::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"nil_method","id":1}')

    assert recorder.exchanges[0].key?("result")
    assert_nil recorder.exchanges[0]["result"]
  end

  def test_keyword_params_recorded
    server = Reclamo::Server.new
    server.expose(Greeter.new("Hi"))
    recorder = Reclamo::Recorder.new(server)
    server.handle('{"jsonrpc":"2.0","method":"greet","params":{"name":"Alice"},"id":1}')

    assert_equal({ "name" => "Alice" }, recorder.exchanges[0]["params"])
  end

  private

  def build_recorded_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    recorder = Reclamo::Recorder.new(server)
    [server, recorder]
  end
end
