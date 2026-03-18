# frozen_string_literal: true

module Reclamo
  class Server
    def initialize
      @handler = Handler.new
    end

    def expose(target, namespace: nil)
      @handler.expose(target, namespace: namespace)
      self
    end

    def expose_method(name, &)
      @handler.expose_method(name, &)
      self
    end

    def handle(json_string)
      data = parse_json(json_string)
      return JSON.generate(Response.error(PARSE_ERROR, nil)) unless data

      data.is_a?(Array) ? handle_batch(data) : handle_single(data)
    end

    def methods_list
      @handler.methods_list
    end

    private

    def parse_json(json_string)
      JSON.parse(json_string)
    rescue JSON::ParserError
      nil
    end

    def handle_batch(requests)
      return JSON.generate(Response.error(INVALID_REQUEST, nil)) if requests.empty?

      responses = requests.filter_map { |req| process_request(req) }
      return nil if responses.empty?

      JSON.generate(responses)
    end

    def handle_single(data)
      result = process_request(data)
      result ? JSON.generate(result) : nil
    end

    def process_request(data)
      request = Request.new(data)
      execute_request(request)
    rescue InvalidRequest
      id = data.is_a?(Hash) ? data["id"] : nil
      Response.error(INVALID_REQUEST, id)
    end

    def execute_request(request)
      result = dispatch(request)
      return nil if request.notification?

      Response.success(result, request.id)
    rescue StandardError => e
      error_response_for(request, e)
    end

    def dispatch(request)
      case request.method_name
      when "rpc.discover"
        { "methods" => @handler.methods_list }
      else
        @handler.call(request.method_name, request.params)
      end
    end

    def error_response_for(request, err)
      return nil if request.notification?

      case err
      when MethodNotFound
        Response.error(METHOD_NOT_FOUND, request.id)
      when ArgumentError
        Response.error(INVALID_PARAMS, request.id, data: err.message)
      else
        Response.error(INTERNAL_ERROR, request.id, data: err.message)
      end
    end
  end
end
