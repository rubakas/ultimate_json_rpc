# frozen_string_literal: true

require "test_helper"
require "reclamo/stdio"
require "json"
require "stringio"

class TestStdio < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_processes_single_request
    input, output = io_for(rpc_json("add", [2, 3]))
    Reclamo::Stdio.new(@server, input: input, output: output).run

    response = parse_output(output)
    assert_equal 5, response["result"]
  end

  def test_processes_multiple_requests
    lines = [rpc_json("add", [1, 2]), rpc_json("add", [3, 4])].join("\n")
    input, output = io_for(lines)
    Reclamo::Stdio.new(@server, input: input, output: output).run

    responses = parse_all_output(output)
    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
    assert_equal 7, responses[1]["result"]
  end

  def test_notification_produces_no_output
    request = JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] })
    input, output = io_for(request)
    Reclamo::Stdio.new(@server, input: input, output: output).run

    assert_empty output_lines(output)
  end

  def test_invalid_json_returns_parse_error
    input, output = io_for("not json")
    Reclamo::Stdio.new(@server, input: input, output: output).run

    response = parse_output(output)
    assert_equal(-32_700, response["error"]["code"])
  end

  def test_skips_empty_lines
    lines = "\n\n#{rpc_json("add", [1, 2])}\n\n"
    input, output = io_for(lines)
    Reclamo::Stdio.new(@server, input: input, output: output).run

    responses = parse_all_output(output)
    assert_equal 1, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_method_not_found
    input, output = io_for(rpc_json("nonexistent"))
    Reclamo::Stdio.new(@server, input: input, output: output).run

    response = parse_output(output)
    assert_equal(-32_601, response["error"]["code"])
  end

  def test_stop_on_unstarted_adapter_is_noop
    adapter = Reclamo::Stdio.new(@server, input: StringIO.new(""), output: StringIO.new)

    refute_predicate adapter, :running?
    adapter.stop
    refute_predicate adapter, :running?
  end

  def test_running_is_false_after_run_completes
    input, output = io_for(rpc_json("add", [1, 2]))
    adapter = Reclamo::Stdio.new(@server, input: input, output: output)
    adapter.run

    refute_predicate adapter, :running?
  end

  def test_epipe_on_output_stops_gracefully
    broken_output = Object.new
    def broken_output.puts(*)
      raise Errno::EPIPE
    end

    def broken_output.flush; end

    lines = [rpc_json("add", [2, 3]), rpc_json("add", [4, 5])].join("\n")
    input = StringIO.new(lines)
    adapter = Reclamo::Stdio.new(@server, input: input, output: broken_output)

    assert_nil adapter.run
    refute_predicate adapter, :running?
  end

  def test_batch_request
    batch = JSON.generate(
      [
        { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
        { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
      ]
    )
    input, output = io_for(batch)
    Reclamo::Stdio.new(@server, input: input, output: output).run

    responses = JSON.parse(parse_output_raw(output))
    assert_equal 2, responses.size
  end

  private

  def rpc_json(method, params = nil, id: 1)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => id }
    request["params"] = params if params
    JSON.generate(request)
  end

  def io_for(input_string)
    [StringIO.new(input_string), StringIO.new]
  end

  def output_lines(output)
    output.rewind
    output.readlines.map(&:chomp).reject(&:empty?)
  end

  def parse_output_raw(output)
    output_lines(output).first
  end

  def parse_output(output)
    JSON.parse(parse_output_raw(output))
  end

  def parse_all_output(output)
    output_lines(output).map { |line| JSON.parse(line) }
  end
end
