# frozen_string_literal: true

require "test_helper"
require "reclamo/websocket"
require "json"

MockEvent = Struct.new(:data)

class TestWebSocket < Minitest::Test
  def test_on_message_returns_response
    ws = build_ws
    response = JSON.parse(ws.on_message('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'))

    assert_equal 5, response["result"]
  end

  def test_on_message_notification_returns_nil
    ws = build_ws

    assert_nil ws.on_message('{"jsonrpc":"2.0","method":"add","params":[2,3]}')
  end

  def test_on_message_parse_error
    ws = build_ws
    response = JSON.parse(ws.on_message("not json"))

    assert_equal(-32_700, response["error"]["code"])
  end

  def test_on_message_method_not_found
    ws = build_ws
    response = JSON.parse(ws.on_message('{"jsonrpc":"2.0","method":"nonexistent","id":1}'))

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_on_message_batch
    ws = build_ws
    batch = '[{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1},' \
            '{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}]'
    responses = JSON.parse(ws.on_message(batch))

    assert_equal 2, responses.size
  end

  def test_call_with_mock_socket
    ws = build_ws
    sent = []
    socket = MockSocket.new(sent)

    ws.call({}, socket)
    socket.trigger(:message, MockEvent.new('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'))

    assert_equal 1, sent.size
    assert_equal 5, JSON.parse(sent[0])["result"]
  end

  def test_call_skips_nil_for_notifications
    ws = build_ws
    sent = []
    socket = MockSocket.new(sent)

    ws.call({}, socket)
    socket.trigger(:message, MockEvent.new('{"jsonrpc":"2.0","method":"add","params":[2,3]}'))

    assert_empty sent
  end

  def test_server_accessor
    server = Reclamo::Server.new
    ws = Reclamo::WebSocket.new(server)

    assert_equal server, ws.server
  end

  private

  def build_ws
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::WebSocket.new(server)
  end
end

class MockSocket
  def initialize(sent)
    @handlers = {}
    @sent = sent
  end

  def on(event, &block)
    @handlers[event] = block
  end

  def send(data)
    @sent << data
  end

  def trigger(event, *)
    @handlers[event]&.call(*)
  end
end
