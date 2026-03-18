# frozen_string_literal: true

module Reclamo
  # @api private
  PARSE_FAILED = Object.new.freeze
  private_constant :PARSE_FAILED

  class Server
    attr_reader :name, :version

    def initialize(name: nil, version: nil)
      @name = name
      @version = version
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
      data = parse_json(json_string)
      handle_parsed(data)
    end

    alias call handle

    def handle_parsed(data)
      return JSON.generate(Response.error(PARSE_ERROR, nil)) if data.equal?(PARSE_FAILED)

      case data
      when Array then handle_batch(data)
      when Hash then serialize_single(data)
      else JSON.generate(Response.error(INVALID_REQUEST, nil))
      end
    end

    def to_proc = method(:call).to_proc
    def inspect = "#<#{self.class}#{" name=#{@name.inspect}" if @name} methods=#{size} middleware=#{@middleware.size}>"

    def freeze
      @handler.freeze
      @middleware.freeze
      super
    end

    def methods_list = @handler.methods_list
    def methods_info = @handler.methods_info
    def method?(method_name) = @handler.method?(method_name)
    def size = @handler.size
    def empty? = @handler.empty?

    private

    def parse_json(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError, TypeError, EncodingError
      PARSE_FAILED
    end

    def handle_batch(requests)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) if requests.empty?

      json_parts = requests.filter_map { |req| serialize_single(req) }
      return nil if json_parts.empty?

      "[#{json_parts.join(",")}]"
    end

    def serialize_single(data)
      request = Request.new(data)
      response = execute_request(request)
      return nil unless response

      JSON.generate(response)
    rescue InvalidRequest
      JSON.generate(Response.error(INVALID_REQUEST, extract_id(data)))
    rescue JSON::JSONError
      id = response.is_a?(Hash) ? response["id"] : nil
      JSON.generate(Response.error(INTERNAL_ERROR, id))
    end

    def extract_id(data)
      return nil unless data.is_a?(Hash)

      id = data["id"]
      id.nil? || id.is_a?(String) || id.is_a?(Numeric) ? id : nil
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
      core = -> { invoke_handler(request) }
      @middleware.reverse_each do |mw|
        prev = core
        core = -> { mw.call(request, prev) }
      end
      core
    end

    def invoke_handler(request)
      return @handler.call(request.method_name, request.params) unless request.method_name == "rpc.discover"

      { "methods" => @handler.methods_info }.tap do |result|
        result["name"] = @name if @name
        result["version"] = @version if @version
      end
    end

    def error_details(err)
      case err
      when MethodNotFound then [METHOD_NOT_FOUND, nil, err.method_name]
      when ApplicationError, ServerError then [err.code, err.message, err.rpc_data]
      when InvalidParams, ArgumentError then [INVALID_PARAMS, nil, err.message]
      else [INTERNAL_ERROR, nil, err.message]
      end
    end
  end
end
