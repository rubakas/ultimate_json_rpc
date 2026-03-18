# frozen_string_literal: true

module Reclamo
  class Request
    attr_reader :method_name, :params, :id

    def initialize(data)
      validate!(data)
      @method_name = data["method"]
      @params = data["params"]
      @id = data["id"]
    end

    def notification?
      !@has_id
    end

    private

    def validate!(data)
      raise InvalidRequest unless data.is_a?(Hash)
      raise InvalidRequest unless data["jsonrpc"] == "2.0"
      raise InvalidRequest unless data["method"].is_a?(String)

      validate_params!(data["params"]) if data.key?("params")

      @has_id = data.key?("id")
    end

    def validate_params!(params)
      raise InvalidRequest unless params.is_a?(Array) || params.is_a?(Hash)
    end
  end

  class InvalidRequest < Error; end
end
