# frozen_string_literal: true

module Reclamo
  GENERIC_ERROR_DATA = "Internal server error"
  private_constant :GENERIC_ERROR_DATA

  class Server
    attr_reader :name, :version, :description, :max_batch_size

    HOOK_EVENTS = %i[request response error].freeze
    private_constant :HOOK_EVENTS

    def initialize(name: nil, version: nil, description: nil, max_batch_size: 100, expose_errors: false)
      @name = name
      @version = version
      @description = description
      @max_batch_size = max_batch_size
      @expose_errors = expose_errors
      @handler = Handler.new
      @middleware = []
      @hooks = HOOK_EVENTS.to_h { |e| [e, []] }
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil, returns: nil)
      @handler.expose(target, namespace: namespace, only: only, except: except,
                              descriptions: descriptions, returns: returns)
      self
    end

    def expose_method(name, callable = nil, description: nil, returns: nil, &)
      @handler.expose_method(name, callable, description: description, returns: returns, &)
      self
    end

    def use(only: nil, except: nil, &block)
      raise ArgumentError, "block required" unless block
      raise ArgumentError, "cannot use both :only and :except" if only && except

      @middleware << [block, middleware_matcher(only, except)]
      self
    end

    def on(event, &block)
      raise ArgumentError, "block required" unless block
      raise ArgumentError, "unknown event: #{event}" unless HOOK_EVENTS.include?(event)

      @hooks[event] << block
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
      @hooks.each_value(&:freeze)
      [@handler, @middleware, @hooks].each(&:freeze)
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
      if over_batch_limit?(requests)
        return JSON.generate(Response.error(INVALID_REQUEST, nil, message: "Batch too large"))
      end

      json_parts = requests.filter_map { |req| serialize_single(req) }
      json_parts.empty? ? nil : "[#{json_parts.join(",")}]"
    end

    def over_batch_limit?(requests) = @max_batch_size && requests.size > @max_batch_size

    def serialize_single(data)
      request = parse_request(data)
      return request unless request.is_a?(Request)

      response = execute_request(request)
      return nil unless response

      JSON.generate(response)
    rescue JSON::JSONError
      JSON.generate(Response.error(INTERNAL_ERROR, response.is_a?(Hash) ? response["id"] : nil))
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
      emit(:request, request)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = build_chain(request).call
      emit(:response, request, result, elapsed(start))
      request.notification? ? nil : Response.success(result, request.id)
    rescue StandardError => e
      emit(:error, request, e, elapsed(start))
      return nil if request.notification?

      code, message, data = error_details(e)
      Response.error(code, request.id, data: data, message: message)
    end

    def emit(event, *args)
      @hooks[event].each { |hook| hook.call(*args) }
    rescue StandardError => e
      Kernel.warn "Reclamo: #{event} hook error: #{e.message}"
    end

    def elapsed(start) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    def build_chain(request)
      applicable = @middleware.select { |_, matcher| matcher.call(request.method_name) }
      applicable.reverse.reduce(-> { invoke_handler(request) }) do |core, (mw, _)|
        -> { mw.call(request, core) }
      end
    end

    def middleware_matcher(only, except)
      return ->(_) { true } unless only || except

      patterns = Array(only || except).map(&:to_s)
      check = only ? :any? : :none?
      ->(name) { patterns.public_send(check) { |p| p.include?("*") ? File.fnmatch(p, name) : p == name } }
    end

    def invoke_handler(request)
      return @handler.call(request.method_name, request.params) unless request.method_name == "rpc.discover"

      build_openrpc_document
    end

    def build_openrpc_document
      doc = { "openrpc" => "1.3.2", "info" => build_info, "methods" => @handler.methods_info }
      doc.delete("info") if doc["info"].empty?
      doc
    end

    def build_info
      { "title" => @name, "version" => @version, "description" => @description }.compact
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
