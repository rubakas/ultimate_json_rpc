# frozen_string_literal: true

module Reclamo
  module Extras
    module TestHelpers
      def rpc_call(server, method, params: nil, id: 1)
        json = rpc_json_adapter(server)
        request = { "jsonrpc" => "2.0", "method" => method, "id" => id }
        request["params"] = params if params
        json.parse(server.handle(json.generate(request)))
      end

      def rpc_notify(server, method, params: nil)
        json = rpc_json_adapter(server)
        request = { "jsonrpc" => "2.0", "method" => method }
        request["params"] = params if params
        server.handle(json.generate(request))
      end

      def rpc_batch(server, *requests)
        json = rpc_json_adapter(server)
        result = server.handle(json.generate(requests))
        result ? json.parse(result) : nil
      end

      def assert_rpc_success(response, expected: :__not_given__, msg: nil)
        assert response.key?("result"), msg || "Expected success response but got error: #{response["error"]&.inspect}"
        refute response.key?("error"), msg || "Expected no error but got: #{response["error"]&.inspect}"
        return if expected == :__not_given__

        expected.nil? ? assert_nil(response["result"], msg) : assert_equal(expected, response["result"], msg)
      end

      def assert_rpc_error(response, code: nil, message: nil, msg: nil)
        assert response.key?("error"), msg || "Expected error response but got result: #{response["result"]&.inspect}"
        refute response.key?("result"), msg || "Expected no result but got: #{response["result"]&.inspect}"
        assert_equal code, response["error"]["code"], msg if code
        assert_equal message, response["error"]["message"], msg if message
      end

      def assert_rpc_notification(server, method, params: nil, msg: nil)
        result = rpc_notify(server, method, params: params)
        assert_nil result, msg || "Expected nil for notification but got: #{result.inspect}"
      end

      private

      def rpc_json_adapter(server)
        server.json_adapter
      end
    end
  end
end
