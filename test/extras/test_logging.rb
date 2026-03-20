# frozen_string_literal: true

require "test_helper"
require "ultimate_json_rpc/extras/logging"
require "json"
require "logger"
require "stringio"

class TestLogging < Minitest::Test
  def test_returns_logging_instance
    server = build_server
    logger = Logger.new(StringIO.new)

    assert_instance_of UltimateJsonRpc::Extras::Logging, UltimateJsonRpc::Extras::Logging.new(server, logger)
  end

  def test_logs_successful_response
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/add/, output.string)
    assert_match(/ms\)/, output.string)
  end

  def test_logs_at_info_level_by_default
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/INFO/, output.string)
  end

  def test_logs_at_custom_level
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output), level: :debug)
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/DEBUG/, output.string)
  end

  def test_logs_errors_at_error_level
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"nonexistent","id":1}')

    assert_match(/ERROR/, output.string)
    assert_match(/nonexistent/, output.string)
    assert_match(/MethodNotFound/, output.string)
  end

  def test_logs_duration
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/\d+\.\d+ms/, output.string)
  end

  def test_logs_method_name
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"divide","params":[6,2],"id":1}')

    assert_match(/divide/, output.string)
  end

  def test_logs_progname
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_match(/UltimateJsonRpc/, output.string)
  end

  def test_notifications_are_logged
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3]}')

    assert_match(/add/, output.string)
  end

  def test_multiple_requests_each_logged
    output = StringIO.new
    server = build_server
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(output))
    server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    server.handle('{"jsonrpc":"2.0","method":"divide","params":[6,3],"id":2}')

    assert_match(/add/, output.string)
    assert_match(/divide/, output.string)
  end

  def test_works_alongside_server_setup
    server = UltimateJsonRpc::Server.new
                                    .expose(Calculator)
                                    .expose_method("ping") { "pong" }
    UltimateJsonRpc::Extras::Logging.new(server, Logger.new(StringIO.new))

    assert_equal 3, server.size
  end

  private

  def build_server
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator)
    server
  end
end
