# frozen_string_literal: true

# WebSocket JSON-RPC server using faye-websocket
#
# Setup: gem install faye-websocket puma
# Run:   bundle exec rackup examples/websocket_server.ru
#
# Test with wscat (npm install -g wscat):
#   wscat -c ws://localhost:9292
#   > {"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}
#   < {"jsonrpc":"2.0","result":5,"id":1}
#
# Or test with JavaScript:
#   const ws = new WebSocket("ws://localhost:9292");
#   ws.onmessage = (e) => console.log(e.data);
#   ws.onopen = () => ws.send('{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}');

require "reclamo"
require "reclamo/transport/websocket"
require "faye/websocket"

module Calculator
  def self.add(a, b) = a + b
  def self.multiply(a, b) = a * b
end

server = Reclamo::Server.new(name: "Calculator WS", version: "1.0")
server.expose(Calculator)
ws_handler = Reclamo::Transport::WebSocket.new(server)

app = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    ws_handler.call(env, ws)
    ws.on(:close) { ws = nil }
    ws.rack_response
  else
    [200, { "content-type" => "text/plain" }, ["WebSocket JSON-RPC server. Connect via ws://localhost:9292"]]
  end
end

run app
