# frozen_string_literal: true

require "test_helper"
require "json"

# A minimal custom JSON serializer for testing
module CustomJSON
  def self.parse(string)
    JSON.parse(string)
  end

  def self.generate(object)
    JSON.generate(object)
  end
end

class TestCustomJSONSerializer < Minitest::Test
  def test_default_uses_stdlib_json
    server = Reclamo::Server.new
    server.expose(Calculator)
    response = JSON.parse(server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'))

    assert_equal 5, response["result"]
  end

  def test_custom_serializer_for_requests
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)
    response = JSON.parse(server.handle('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'))

    assert_equal 5, response["result"]
  end

  def test_custom_serializer_parse_error
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)
    response = JSON.parse(server.handle("not json"))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_custom_serializer_with_notifications
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)

    assert_nil server.handle('{"jsonrpc":"2.0","method":"add","params":[1,2]}')
  end

  def test_custom_serializer_with_batch
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)
    batch = '[{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1},' \
            '{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}]'
    responses = JSON.parse(server.handle(batch))

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_custom_serializer_with_discover
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)
    response = JSON.parse(server.handle('{"jsonrpc":"2.0","method":"rpc.discover","id":1}'))

    assert response["result"].key?("methods")
  end

  def test_custom_serializer_with_invalid_request
    server = Reclamo::Server.new(json: CustomJSON)
    response = JSON.parse(server.handle('"just a string"'))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_custom_serializer_with_handle_parsed
    server = Reclamo::Server.new(json: CustomJSON)
    server.expose(Calculator)
    data = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    response = JSON.parse(server.handle_parsed(data))

    assert_equal 3, response["result"]
  end
end

# Serializer that raises a non-JSON::ParserError on invalid input
module StrictSerializer
  class ParseError < StandardError; end

  def self.parse(string)
    raise ParseError, "invalid" if string.strip.empty?

    JSON.parse(string)
  end

  def self.generate(object)
    JSON.generate(object)
  end
end

class TestCustomSerializerParseErrors < Minitest::Test
  def test_catches_custom_parse_errors
    server = Reclamo::Server.new(json: StrictSerializer)
    server.expose(Calculator)
    response = JSON.parse(server.handle(""))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_catches_custom_parse_errors_for_whitespace
    server = Reclamo::Server.new(json: StrictSerializer)
    server.expose(Calculator)
    response = JSON.parse(server.handle("   "))

    assert_equal(-32_700, response["error"]["code"])
  end
end
