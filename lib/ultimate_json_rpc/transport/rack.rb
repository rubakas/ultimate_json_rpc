# frozen_string_literal: true

module UltimateJsonRpc
  module Transport
    class Rack
      CONTENT_TYPE = { "content-type" => "application/json" }.freeze
      NOT_ALLOWED_BODY = '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Method Not Allowed"},"id":null}'
      NOT_ALLOWED_HEADERS = CONTENT_TYPE.merge("allow" => "POST").freeze
      UNSUPPORTED_MEDIA_BODY = '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Unsupported Media Type"},"id":null}'

      def initialize(server)
        @server = server
      end

      def call(env)
        return [200, CONTENT_TYPE.dup, []] if env["REQUEST_METHOD"] == "HEAD"
        return method_not_allowed unless env["REQUEST_METHOD"] == "POST"
        return unsupported_media_type unless acceptable_content_type?(env)

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

      def unsupported_media_type
        [415, CONTENT_TYPE.dup, [UNSUPPORTED_MEDIA_BODY]]
      end

      def acceptable_content_type?(env)
        ct = env["CONTENT_TYPE"]
        ct.nil? || ct.empty? || ct.start_with?("application/json")
      end
    end
  end
end
