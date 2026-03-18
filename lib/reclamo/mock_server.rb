# frozen_string_literal: true

module Reclamo
  class MockServer
    def initialize
      @stubs = {}
      @any_stubs = {}
    end

    def stub(method, params, result)
      @stubs[[method.to_s, normalize(params)]] = result
      self
    end

    def stub_any(method, result)
      @any_stubs[method.to_s] = result
      self
    end

    def handle(json_string)
      handle_parsed(JSON.parse(json_string))
    rescue JSON::ParserError, TypeError, EncodingError
      JSON.generate(Response.error(PARSE_ERROR, nil))
    end

    def handle_parsed(data)
      case data
      when Array then handle_batch(data)
      when Hash then handle_single(data)
      else JSON.generate(Response.error(INVALID_REQUEST, nil))
      end
    end

    private

    def handle_batch(requests)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) if requests.empty?

      parts = requests.filter_map { |req| handle_single(req) }
      parts.empty? ? nil : "[#{parts.join(",")}]"
    end

    def handle_single(data)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) unless valid_request?(data)

      method = data["method"]
      params = data["params"]
      id = data["id"]
      result = lookup(method, params)

      return nil unless id

      if result == :__no_stub__
        JSON.generate(Response.error(METHOD_NOT_FOUND, id, data: method))
      else
        JSON.generate(Response.success(result, id))
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
      data.is_a?(Hash) && data["jsonrpc"] == "2.0" && data["method"].is_a?(String)
    end
  end
end
