# frozen_string_literal: true

module Reclamo
  class WebSocket
    attr_reader :server

    def initialize(server)
      @server = server
    end

    def on_message(data)
      response = @server.handle(data.to_s)
      return nil unless response

      response
    end

    def call(_env, socket)
      socket.on(:message) do |event|
        response = on_message(event.respond_to?(:data) ? event.data : event)
        socket.send(response) if response
      end
    end
  end
end
