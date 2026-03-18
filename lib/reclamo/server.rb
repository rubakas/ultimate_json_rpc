# frozen_string_literal: true

module Reclamo
  # @api private
  PARSE_FAILED = Object.new.freeze
  private_constant :PARSE_FAILED

  class Server
    def initialize
      @handler = Handler.new
      @middleware = []
    end

    def expose(target, namespace: nil, only: nil, except: nil)
      @handler.expose(target, namespace: namespace, only: only, except: except)
      self
    end

    def expose_method(name, &)
      @handler.expose_method(name, &)
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

    def handle_parsed(data)
      return JSON.generate(Response.error(PARSE_ERROR, nil)) if data.equal?(PARSE_FAILED)

      case data
      when Array then handle_batch(data)
      when Hash then handle_single(data)
      else JSON.generate(Response.error(INVALID_REQUEST, nil))
      end
    end

    def methods_list = @handler.methods_list
    def methods_info = @handler.methods_info
    def method?(method_name) = @handler.method?(method_name)
    def size = @handler.size

    private

    def parse_json(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError, TypeError
      PARSE_FAILED
    end

    def handle_batch(requests)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) if requests.empty?

      json_parts = requests.filter_map { |req| serialize_single(req) }
      return nil if json_parts.empty?

      "[#{json_parts.join(",")}]"
    end

    def handle_single(data)
      serialize_single(data)
    end

    def serialize_single(data)
      response = process_request(data)
      return nil unless response

      JSON.generate(response)
    rescue JSON::JSONError
      id = response.is_a?(Hash) ? response["id"] : nil
      JSON.generate(Response.error(INTERNAL_ERROR, id))
    end

    def process_request(data)
      request = Request.new(data)
      execute_request(request)
    rescue InvalidRequest
      Response.error(INVALID_REQUEST, extract_id(data))
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
      error_response_for(request, e)
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
      return { "methods" => @handler.methods_info } if request.method_name == "rpc.discover"

      @handler.call(request.method_name, request.params)
    end

    def error_response_for(request, err)
      return nil if request.notification?

      code, message, data = error_details(err)
      Response.error(code, request.id, data: data, message: message)
    end

    def error_details(err)
      case err
      when MethodNotFound then [METHOD_NOT_FOUND, nil, nil]
      when ApplicationError then [err.code, err.message, err.rpc_data]
      when ArgumentError then [INVALID_PARAMS, nil, err.message]
      else [INTERNAL_ERROR, nil, err.message]
      end
    end
  end
end
