# frozen_string_literal: true

module Reclamo
  module Transport
    class Rack
      CONTENT_TYPE = { "content-type" => "application/json" }.freeze
      NOT_ALLOWED_BODY = '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Method Not Allowed"},"id":null}'
      NOT_ALLOWED_HEADERS = CONTENT_TYPE.merge("allow" => "POST").freeze

      def initialize(server)
        @server = server
      end

      def call(env)
        return [200, CONTENT_TYPE.dup, []] if env["REQUEST_METHOD"] == "HEAD"
        return method_not_allowed unless env["REQUEST_METHOD"] == "POST"

        body = env["rack.input"]&.read.to_s
        response = @server.handle(body)

        if response
          [200, CONTENT_TYPE.dup, [response]]
        else
          [204, {}, []]
        end
      end

      def freeze
        @server.freeze
        super
      end

      private

      def method_not_allowed
        [405, NOT_ALLOWED_HEADERS.dup, [NOT_ALLOWED_BODY]]
      end
    end
  end
end
