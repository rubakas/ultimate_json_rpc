# frozen_string_literal: true

require "test_helper"
require "reclamo/logging"
require "json"
require "logger"
require "stringio"

class TestLogging < Minitest::Test
  def test_log_to_returns_self
    server = build_server
    logger = Logger.new(StringIO.new)

    assert_equal server, server.log_to(logger)
  end

  def test_logs_successful_response
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/add/, output.string)
    assert_match(/ms\)/, output.string)
  end

  def test_logs_at_info_level_by_default
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/INFO/, output.string)
  end

  def test_logs_at_custom_level
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output), level: :debug)
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/DEBUG/, output.string)
  end

  def test_logs_errors_at_error_level
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"nonexistent","id":1}')

    assert_match(/ERROR/, output.string)
    assert_match(/nonexistent/, output.string)
    assert_match(/MethodNotFound/, output.string)
  end

  def test_logs_duration
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/\d+\.\d+ms/, output.string)
  end

  def test_logs_method_name
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"divide","params":[6,2],"id":1}')

    assert_match(/divide/, output.string)
  end

  def test_logs_progname
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/Reclamo/, output.string)
  end

  def test_notifications_are_logged
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3]}')

    assert_match(/add/, output.string)
  end

  def test_multiple_requests_each_logged
    output = StringIO.new
    server = build_server
    server.log_to(Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    server.handle('{"jsonrpc":"2.0","method":"divide","params":[6,3],"id":2}')

    assert_match(/add/, output.string)
    assert_match(/divide/, output.string)
  end

  def test_chainable_with_other_setup
    server = Reclamo::Server.new
                            .expose(Calculator)
                            .log_to(Logger.new(StringIO.new))
                            .expose_method("ping") { "pong" }

    assert_equal 3, server.size
  end

  private

  def build_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    server
  end
end
