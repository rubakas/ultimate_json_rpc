# frozen_string_literal: true

require "test_helper"
require "reclamo/transport/websocket"
require "json"

class TestWebSocket < Minitest::Test
  MockEvent = Struct.new(:data)

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
    ws = Reclamo::Transport::WebSocket.new(server)

    assert_equal server, ws.server
  end

  def test_call_with_raw_string_event
    ws = build_ws
    sent = []
    socket = MockSocket.new(sent)

    ws.call({}, socket)
    socket.trigger(:message, '{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

    assert_equal 1, sent.size
    assert_equal 5, JSON.parse(sent[0])["result"]
  end

  def test_freeze_delegates_to_server
    ws = build_ws
    ws.freeze

    assert_predicate ws, :frozen?
    assert_predicate ws.server, :frozen?
  end

  def test_frozen_websocket_handles_messages
    ws = build_ws
    ws.freeze

    response = JSON.parse(ws.on_message('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}'))

    assert_equal 5, response["result"]
  end

  private

  def build_ws
    server = Reclamo::Server.new
    server.expose(Calculator)
    Reclamo::Transport::WebSocket.new(server)
  end
end
