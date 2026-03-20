# frozen_string_literal: true

require "test_helper"
require "json"

class TestMethodLevelMiddlewareOnly < Minitest::Test
  def setup
    @server = UltimateJsonRpc::Server.new
    @server.expose(Calculator)
    @server.expose_method("ping") { "pong" }
  end

  def test_only_runs_middleware_for_matching_method
    called_for = []
    @server.use(only: ["add"]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("divide", [10, 2])

    assert_equal ["add"], called_for
  end

  def test_only_with_multiple_methods
    called_for = []
    @server.use(only: %w[add ping]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("divide", [10, 2])
    call_method("ping")

    assert_equal %w[add ping], called_for
  end

  def test_only_with_glob_pattern
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, namespace: "calc")
    server.expose_method("ping") { "pong" }

    called_for = []
    server.use(only: ["calc.*"]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("calc.add", [1, 2], server: server)
    call_method("calc.divide", [10, 2], server: server)
    call_method("ping", nil, server: server)

    assert_equal %w[calc.add calc.divide], called_for
  end

  def test_only_with_single_string_instead_of_array
    called_for = []
    @server.use(only: "add") do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("divide", [10, 2])

    assert_equal ["add"], called_for
  end

  def test_only_with_symbol
    called_for = []
    @server.use(only: :add) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("divide", [10, 2])

    assert_equal ["add"], called_for
  end

  private

  def call_method(method, params = nil, server: @server)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(server.handle(JSON.generate(request)))
  end
end

class TestMethodLevelMiddlewareExcept < Minitest::Test
  def setup
    @server = UltimateJsonRpc::Server.new
    @server.expose(Calculator)
    @server.expose_method("ping") { "pong" }
  end

  def test_except_skips_middleware_for_matching_method
    called_for = []
    @server.use(except: ["ping"]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("divide", [10, 2])
    call_method("ping")

    assert_equal %w[add divide], called_for
  end

  def test_except_with_glob_pattern
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, namespace: "calc")
    server.expose_method("ping") { "pong" }

    called_for = []
    server.use(except: ["calc.*"]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("calc.add", [1, 2], server: server)
    call_method("ping", nil, server: server)

    assert_equal ["ping"], called_for
  end

  def test_except_with_single_string
    called_for = []
    @server.use(except: "ping") do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("add", [1, 2])
    call_method("ping")

    assert_equal ["add"], called_for
  end

  private

  def call_method(method, params = nil, server: @server)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(server.handle(JSON.generate(request)))
  end
end

class TestMethodLevelMiddlewareEdgeCases < Minitest::Test
  def test_only_and_except_raises
    server = UltimateJsonRpc::Server.new

    error = assert_raises(ArgumentError) do
      server.use(only: ["add"], except: ["divide"]) { |_r, n| n.call }
    end

    assert_equal "cannot use both :only and :except", error.message
  end

  def test_global_and_scoped_middleware_chain_order
    log = []
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use do |_request, next_call|
      log << "global:before"
      next_call.call.tap { log << "global:after" }
    end

    server.use(only: ["add"]) do |_request, next_call|
      log << "scoped:before"
      next_call.call.tap { log << "scoped:after" }
    end

    call_method("add", [1, 2], server: server)
    assert_equal %w[global:before scoped:before scoped:after global:after], log

    log.clear
    call_method("divide", [10, 2], server: server)
    assert_equal %w[global:before global:after], log
  end

  def test_scoped_middleware_can_transform_result
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["add"]) do |_request, next_call|
      next_call.call * 10
    end

    response = call_method("add", [2, 3], server: server)
    assert_equal 50, response["result"]

    response = call_method("divide", [10, 2], server: server)
    assert_equal 5.0, response["result"]
  end

  def test_scoped_middleware_can_reject_request
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["divide"]) do |_request, _next_call|
      raise UltimateJsonRpc::Core::ApplicationError.new(code: 403, message: "Division forbidden")
    end

    response = call_method("divide", [10, 2], server: server)
    assert_equal 403, response["error"]["code"]

    response = call_method("add", [1, 2], server: server)
    assert_equal 3, response["result"]
  end

  def test_multiple_scoped_middleware_different_targets
    log = []
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["add"]) do |_request, next_call|
      log << "add-mw"
      next_call.call
    end

    server.use(only: ["divide"]) do |_request, next_call|
      log << "divide-mw"
      next_call.call
    end

    call_method("add", [1, 2], server: server)
    assert_equal ["add-mw"], log

    log.clear
    call_method("divide", [10, 2], server: server)
    assert_equal ["divide-mw"], log
  end

  def test_scoped_middleware_with_notifications
    called = false
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["add"]) do |_request, next_call|
      called = true
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    assert_nil server.handle(JSON.generate(request))
    assert called
  end

  def test_scoped_middleware_skipped_for_notifications_on_non_matching
    called = false
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["divide"]) do |_request, next_call|
      called = true
      next_call.call
    end

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }
    server.handle(JSON.generate(request))
    refute called
  end

  def test_scoped_middleware_applies_to_rpc_discover
    called = false
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(only: ["rpc.discover"]) do |_request, next_call|
      called = true
      next_call.call
    end

    response = call_method("rpc.discover", nil, server: server)
    assert called
    assert response["result"].key?("methods")
  end

  def test_except_rpc_discover_skips_for_discover
    called = false
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)

    server.use(except: ["rpc.discover"]) do |_request, next_call|
      called = true
      next_call.call
    end

    call_method("rpc.discover", nil, server: server)
    refute called

    call_method("add", [1, 2], server: server)
    assert called
  end

  def test_freeze_works_with_scoped_middleware
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    server.use(only: ["add"]) { |_r, n| n.call }
    server.freeze

    assert_raises(FrozenError) { server.use { |_r, n| n.call } }

    response = call_method("add", [1, 2], server: server)
    assert_equal 3, response["result"]
  end

  def test_use_returns_self_with_only
    server = UltimateJsonRpc::Server.new
    result = server.use(only: ["add"]) { |_r, n| n.call }
    assert_equal server, result
  end

  def test_use_returns_self_with_except
    server = UltimateJsonRpc::Server.new
    result = server.use(except: ["add"]) { |_r, n| n.call }
    assert_equal server, result
  end

  def test_only_and_except_on_separate_middleware_compose
    log = []
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    server.expose_method("ping") { "pong" }

    server.use(only: %w[add divide]) do |request, next_call|
      log << "only:#{request.method_name}"
      next_call.call
    end

    server.use(except: ["divide"]) do |request, next_call|
      log << "except:#{request.method_name}"
      next_call.call
    end

    call_method("add", [1, 2], server: server)
    assert_equal %w[only:add except:add], log

    log.clear
    call_method("divide", [10, 2], server: server)
    assert_equal %w[only:divide], log

    log.clear
    call_method("ping", nil, server: server)
    assert_equal %w[except:ping], log
  end

  def test_glob_pattern_does_not_match_partial_name
    server = UltimateJsonRpc::Server.new
    server.expose_method("admin_panel") { "panel" }
    server.expose_method("admin.create") { "created" }

    called_for = []
    server.use(only: ["admin.*"]) do |request, next_call|
      called_for << request.method_name
      next_call.call
    end

    call_method("admin_panel", nil, server: server)
    call_method("admin.create", nil, server: server)

    assert_equal ["admin.create"], called_for
  end

  private

  def call_method(method, params = nil, server:)
    request = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    request["params"] = params if params
    JSON.parse(server.handle(JSON.generate(request)))
  end
end
