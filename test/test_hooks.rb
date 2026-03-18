# frozen_string_literal: true

require "test_helper"
require "json"

class TestHooksOnRequest < Minitest::Test
  def test_on_request_fires_before_dispatch
    server = build_server
    captured = nil
    server.on(:request) { |req| captured = req.method_name }

    call(server, "add", [1, 2])
    assert_equal "add", captured
  end

  def test_on_request_fires_for_notifications
    server = build_server
    called = false
    server.on(:request) { |_req| called = true }

    notify(server, "add", [1, 2])
    assert called
  end

  def test_multiple_request_hooks
    server = build_server
    log = []
    server.on(:request) { |_req| log << "first" }
    server.on(:request) { |_req| log << "second" }

    call(server, "add", [1, 2])
    assert_equal %w[first second], log
  end

  private

  def build_server
    Reclamo::Server.new.tap { |s| s.expose(Calculator) }
  end

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    server.handle(JSON.generate(request))
  end

  def notify(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params }
    server.handle(JSON.generate(request))
  end
end

class TestHooksOnResponse < Minitest::Test
  def test_on_response_fires_with_result_and_duration
    server = build_server
    captured = {}
    server.on(:response) do |req, result, duration|
      captured[:method] = req.method_name
      captured[:result] = result
      captured[:duration] = duration
    end

    call(server, "add", [2, 3])
    assert_equal "add", captured[:method]
    assert_equal 5, captured[:result]
    assert_kind_of Float, captured[:duration]
    assert_operator captured[:duration], :>=, 0
  end

  def test_on_response_fires_for_notifications
    server = build_server
    captured_result = :not_set
    server.on(:response) { |_req, result, _dur| captured_result = result }

    notify(server, "add", [1, 2])
    assert_equal 3, captured_result
  end

  def test_on_response_does_not_fire_on_error
    server = build_server
    called = false
    server.on(:response) { |_req, _result, _dur| called = true }

    call(server, "nonexistent")
    refute called
  end

  private

  def build_server = Reclamo::Server.new.tap { |s| s.expose(Calculator) }

  def call(server, method, params = nil)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    server.handle(JSON.generate(request))
  end

  def notify(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params }
    server.handle(JSON.generate(request))
  end
end

class TestHooksOnError < Minitest::Test
  def test_on_error_fires_with_exception_and_duration
    server = build_server
    captured = {}
    server.on(:error) do |req, err, duration|
      captured[:method] = req.method_name
      captured[:error_class] = err.class
      captured[:duration] = duration
    end

    call(server, "nonexistent")
    assert_equal "nonexistent", captured[:method]
    assert_equal Reclamo::MethodNotFound, captured[:error_class]
    assert_kind_of Float, captured[:duration]
  end

  def test_on_error_fires_for_notification_errors
    server = build_server
    captured_error = nil
    server.on(:error) { |_req, err, _dur| captured_error = err }

    notify(server, "nonexistent")
    assert_instance_of Reclamo::MethodNotFound, captured_error
  end

  def test_on_error_does_not_fire_on_success
    server = build_server
    called = false
    server.on(:error) { |_req, _err, _dur| called = true }

    call(server, "add", [1, 2])
    refute called
  end

  private

  def build_server = Reclamo::Server.new.tap { |s| s.expose(Calculator) }

  def call(server, method, params = nil)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    server.handle(JSON.generate(request))
  end

  def notify(server, method)
    server.handle(JSON.generate({ "jsonrpc" => "2.0", "method" => method }))
  end
end

class TestHooksEdgeCases < Minitest::Test
  def test_on_returns_self
    server = Reclamo::Server.new
    assert_equal server, server.on(:request) { |x| x }
  end

  def test_on_without_block_raises
    assert_raises(ArgumentError) { Reclamo::Server.new.on(:request) }
  end

  def test_on_unknown_event_raises
    error = assert_raises(ArgumentError) { Reclamo::Server.new.on(:unknown) { |x| x } }
    assert_includes error.message, "unknown event"
  end

  def test_first_hook_error_does_not_break_second_hook
    server = Reclamo::Server.new
    server.expose(Calculator)
    log = []
    server.on(:request) { |_req| raise "first broke" }
    server.on(:request) { |_req| log << "second" }

    assert_output(nil, /first broke/) { call(server, "add", [1, 2]) }
    assert_equal %w[second], log
  end

  def test_hook_error_does_not_break_dispatch
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.on(:request) { |_req| raise "hook broke" }

    response = JSON.parse(call(server, "add", [1, 2]))
    assert_equal 3, response["result"]
  end

  def test_hook_error_warns
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.on(:request) { |_req| raise "hook broke" }

    assert_output(nil, /Reclamo: request hook error: hook broke/) do
      call(server, "add", [1, 2])
    end
  end

  def test_broken_response_hook_warns
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.on(:response) { |_req, _result, _dur| raise "response hook broke" }

    assert_output(nil, /Reclamo: response hook error: response hook broke/) do
      call(server, "add", [1, 2])
    end
  end

  def test_broken_error_hook_warns
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.on(:error) { |_req, _err, _dur| raise "error hook broke" }

    assert_output(nil, /Reclamo: error hook error: error hook broke/) do
      call(server, "nonexistent")
    end
  end

  def test_broken_response_hook_does_not_break_dispatch
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.on(:response) { |_req, _result, _dur| raise "response hook broke" }

    response = JSON.parse(call(server, "add", [1, 2]))
    assert_equal 3, response["result"]
  end

  def test_hooks_survive_freeze
    server = Reclamo::Server.new
    server.expose(Calculator)
    called = false
    server.on(:request) { |_req| called = true }
    server.freeze

    assert_raises(FrozenError) { server.on(:request) { |x| x } }
    call(server, "add", [1, 2])
    assert called
  end

  def test_on_request_fires_for_rpc_discover
    server = Reclamo::Server.new
    server.expose(Calculator)
    captured = nil
    server.on(:request) { |req| captured = req.method_name }

    call(server, "rpc.discover")
    assert_equal "rpc.discover", captured
  end

  private

  def call(server, method, params = nil)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    server.handle(JSON.generate(request))
  end
end
