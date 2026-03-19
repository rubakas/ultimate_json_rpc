# frozen_string_literal: true

module Reclamo
  module Extras
    class MockServer
      def initialize(json: JSON)
        @stubs = {}
        @any_stubs = {}
        @json = json
      end

      def stub(method, params:, result:)
        @stubs[[method.to_s, normalize(params)]] = result
        self
      end

      def stub_any(method, result)
        @any_stubs[method.to_s] = result
        self
      end

      def handle(json_string)
        handle_parsed(@json.parse(json_string))
      rescue StandardError
        @json.generate(Core::Response.error(Core::PARSE_ERROR, nil))
      end

      def handle_parsed(data)
        case data
        when Array then handle_batch(data)
        when Hash then handle_single(data)
        else @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil))
        end
      end

      private

      def handle_batch(requests)
        return @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil)) if requests.empty?

        parts = requests.filter_map { |req| handle_single(req) }
        parts.empty? ? nil : "[#{parts.join(",")}]"
      end

      def handle_single(data)
        return @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil)) unless valid_request?(data)
        return nil unless data.key?("id")

        dispatch_stub(data)
      rescue StandardError
        @json.generate(Core::Response.error(Core::INTERNAL_ERROR, data.is_a?(Hash) ? data["id"] : nil))
      end

      def dispatch_stub(data)
        result = lookup(data["method"], data["params"])
        if result == :__no_stub__
          @json.generate(Core::Response.error(Core::METHOD_NOT_FOUND, data["id"], data: data["method"]))
        else
          @json.generate(Core::Response.success(result, data["id"]))
        end
      end

      def lookup(method, params)
        key = [method, normalize(params)]
        return @stubs[key] if @stubs.key?(key)
        return @any_stubs[method] if @any_stubs.key?(method)

        :__no_stub__
      end

      def normalize(params)
        params.is_a?(Hash) ? params.transform_keys(&:to_s) : params
      end

      def valid_request?(data)
        data.is_a?(Hash) && data["jsonrpc"] == "2.0" && data["method"].is_a?(String) && valid_id?(data)
      end

      def valid_id?(data)
        return true unless data.key?("id")

        id = data["id"]
        id.nil? || id.is_a?(String) || id.is_a?(Numeric)
      end
    end
  end
end
