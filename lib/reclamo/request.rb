# frozen_string_literal: true

module Reclamo
  class Request
    attr_reader :method_name, :params, :id

    def initialize(data)
      validate!(data)
      @method_name = data["method"].freeze
      @params = deep_freeze(data["params"])
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
      raise InvalidRequest, "request must be a JSON object" unless data.is_a?(Hash)
      raise InvalidRequest, "jsonrpc must be \"2.0\"" unless data["jsonrpc"] == "2.0"

      valid_method = data["method"].is_a?(String) && !data["method"].empty?
      raise InvalidRequest, "method must be a non-empty String" unless valid_method
    end

    def validate_params!(params)
      return if params.is_a?(Array) || params.is_a?(Hash)

      raise InvalidRequest, "params must be an Array or Object"
    end

    def validate_id!(id)
      return if id.nil? || id.is_a?(String) || id.is_a?(Numeric)

      raise InvalidRequest, "id must be a String, Number, or Null"
    end

    def deep_freeze(obj)
      case obj
      when Hash then obj.each_value { |v| deep_freeze(v) }
      when Array then obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end
  end
end
