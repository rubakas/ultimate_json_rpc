# frozen_string_literal: true

module Reclamo
  class Request
    attr_reader :method_name, :params, :id

    def initialize(data)
      validate!(data)
      @method_name = data["method"].freeze
      @params = data["params"].freeze
      @id = data["id"].freeze
    end

    def notification?
      !@has_id
    end

    private

    def validate!(data)
      validate_structure!(data)
      validate_params!(data["params"]) if data.key?("params")
      @has_id = data.key?("id")
      validate_id!(data["id"]) if @has_id
    end

    def validate_structure!(data)
      raise InvalidRequest unless data.is_a?(Hash)
      raise InvalidRequest unless data["jsonrpc"] == "2.0"
      raise InvalidRequest unless data["method"].is_a?(String) && !data["method"].empty?
    end

    def validate_params!(params)
      raise InvalidRequest unless params.is_a?(Array) || params.is_a?(Hash)
    end

    def validate_id!(id)
      raise InvalidRequest unless id.nil? || id.is_a?(String) || id.is_a?(Numeric)
    end
  end
end
