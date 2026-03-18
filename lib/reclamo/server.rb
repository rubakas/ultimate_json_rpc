# frozen_string_literal: true

module Reclamo
  GENERIC_ERROR_DATA = "Internal server error"
  private_constant :GENERIC_ERROR_DATA

  class Server
    attr_reader :name, :version, :description, :max_batch_size

    def initialize(name: nil, version: nil, description: nil, max_batch_size: 100, expose_errors: false)
      @name = name
      @version = version
      @description = description
      @max_batch_size = max_batch_size
      @expose_errors = expose_errors
      @handler = Handler.new
      @middleware = []
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil)
      @handler.expose(target, namespace: namespace, only: only, except: except, descriptions: descriptions)
      self
    end

    def expose_method(name, callable = nil, description: nil, &)
      @handler.expose_method(name, callable, description: description, &)
      self
    end

    def use(&block)
      raise ArgumentError, "block required" unless block

      @middleware << block
      self
    end

    def handle(json_string)
      handle_parsed(JSON.parse(json_string))
    rescue JSON::ParserError, TypeError, EncodingError
      JSON.generate(Response.error(PARSE_ERROR, nil))
    end

    alias call handle

    def handle_parsed(data)
      case data
      when Array then handle_batch(data)
      when Hash then serialize_single(data)
      else JSON.generate(Response.error(INVALID_REQUEST, nil))
      end
    end

    def to_proc = method(:call).to_proc
    def inspect = "#<#{self.class}#{" name=#{@name.inspect}" if @name} methods=#{size} middleware=#{@middleware.size}>"
    def expose_errors? = @expose_errors

    def freeze
      [@handler, @middleware].each(&:freeze)
      super
    end

    def methods_list = @handler.methods_list
    def methods_info = @handler.methods_info
    def method?(method_name) = @handler.method?(method_name)
    def size = @handler.size
    def empty? = @handler.empty?

    private

    def handle_batch(requests)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) if requests.empty?

      if @max_batch_size && requests.size > @max_batch_size
        return JSON.generate(Response.error(INVALID_REQUEST, nil, message: "Batch too large"))
      end

      json_parts = requests.filter_map { |req| serialize_single(req) }
      return nil if json_parts.empty?

      "[#{json_parts.join(",")}]"
    end

    def serialize_single(data)
      request = parse_request(data)
      return request unless request.is_a?(Request)

      response = execute_request(request)
      return nil unless response

      begin
        JSON.generate(response)
      rescue JSON::JSONError
        id = response.is_a?(Hash) ? response["id"] : nil
        JSON.generate(Response.error(INTERNAL_ERROR, id))
      end
    end

    def parse_request(data)
      Request.new(data)
    rescue InvalidRequest
      JSON.generate(Response.error(INVALID_REQUEST, extract_id(data)))
    end

    def extract_id(data)
      return nil unless data.is_a?(Hash)

      data["id"].then { |id| id.nil? || id.is_a?(String) || id.is_a?(Numeric) ? id : nil }
    end

    def execute_request(request)
      result = build_chain(request).call
      return nil if request.notification?

      Response.success(result, request.id)
    rescue StandardError => e
      return nil if request.notification?

      code, message, data = error_details(e)
      Response.error(code, request.id, data: data, message: message)
    end

    def build_chain(request)
      @middleware.reverse.reduce(-> { invoke_handler(request) }) do |core, mw|
        -> { mw.call(request, core) }
      end
    end

    def invoke_handler(request)
      return @handler.call(request.method_name, request.params) unless request.method_name == "rpc.discover"

      result = { "methods" => @handler.methods_info }
      { "name" => @name, "version" => @version, "description" => @description }.each { |k, v| result[k] = v if v }
      result
    end

    def error_details(err)
      case err
      when MethodNotFound then [METHOD_NOT_FOUND, nil, err.method_name]
      when ApplicationError, ServerError then [err.code, err.message, err.rpc_data]
      when InvalidParams then [INVALID_PARAMS, nil, err.message]
      when ArgumentError then [INVALID_PARAMS, nil, @expose_errors ? err.message : GENERIC_ERROR_DATA]
      else [INTERNAL_ERROR, nil, @expose_errors ? err.message : GENERIC_ERROR_DATA]
      end
    end
  end
end
