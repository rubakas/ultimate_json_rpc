# frozen_string_literal: true

require "timeout"

module Reclamo
  GENERIC_ERROR_DATA = "Internal server error"
  GENERIC_PARAMS_DATA = "Invalid method parameters"
  private_constant :GENERIC_ERROR_DATA, :GENERIC_PARAMS_DATA

  module BatchProcessor
    private

    def handle_batch(requests)
      return @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil)) if requests.empty?
      if batch_too_large?(requests)
        return @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil, data: "Batch too large"))
      end

      json_parts = process_batch_items(requests)
      json_parts.empty? ? nil : "[#{json_parts.join(",")}]"
    end

    def process_batch_items(requests)
      if @concurrent_batches
        pool_dispatch(requests).compact
      else
        requests.filter_map { |req| serialize_single(req) }
      end
    end

    def pool_dispatch(requests)
      queue = Queue.new
      requests.each_with_index { |req, i| queue << [req, i] }
      results = Array.new(requests.size)
      spawn_workers(queue:, results:, pool_size: [requests.size, @max_concurrency].min)
      results
    end

    def spawn_workers(queue:, results:, pool_size:)
      mutex = Mutex.new
      pool_size.times.map do
        Thread.new { drain_queue(queue, results, mutex) }
      end.each(&:join)
    end

    def drain_queue(queue, results, mutex)
      loop do
        req, i = begin
          queue.pop(true)
        rescue ThreadError
          break
        end
        result = safe_serialize(req)
        mutex.synchronize { results[i] = result }
      end
    end

    def safe_serialize(data)
      serialize_single(data)
    rescue Exception # rubocop:disable Lint/RescueException -- worker threads must never die silently
      id = data.is_a?(Hash) ? extract_id(data) : nil
      begin
        @json.generate(Core::Response.error(Core::INTERNAL_ERROR, id))
      rescue Exception # rubocop:disable Lint/RescueException
        id_json = format_fallback_id(id)
        "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"},\"id\":#{id_json}}"
      end
    end

    def format_fallback_id(id)
      case id
      when Numeric then id.to_s
      when String then JSON.generate(id) rescue "null" # rubocop:disable Style/RescueModifier
      else "null"
      end
    end

    def batch_too_large?(requests) = @max_batch_size && requests.size > @max_batch_size
  end
  private_constant :BatchProcessor

  module OpenRPCBuilder
    private

    def build_openrpc_document
      doc = { "openrpc" => "1.3.2", "info" => build_info, "methods" => @handler.methods_info }
      doc.delete("info") if doc["info"].empty?
      doc["components"] = { "errors" => @error_catalog } if @error_catalog&.any?
      doc
    end

    def build_info
      { "title" => @name, "version" => @version, "description" => @description }.compact
    end
  end
  private_constant :OpenRPCBuilder

  module ServerExtensions
    def register_error(code:, message:, description: nil)
      raise ArgumentError, "error code must be an Integer" unless code.is_a?(Integer)

      if code.between?(Core::RESERVED_ERROR_MIN, Core::RESERVED_ERROR_MAX)
        raise ArgumentError,
              "error code #{code} is in the reserved JSON-RPC range " \
              "(#{Core::RESERVED_ERROR_MIN}..#{Core::RESERVED_ERROR_MAX})"
      end

      @error_catalog ||= []
      raise ArgumentError, "error code #{code} is already registered" if @error_catalog.any? { |e| e["code"] == code }

      entry = { "code" => code, "message" => message.to_s }
      entry["data"] = description.to_s if description
      @error_catalog << entry
      self
    end

    def authorize(*patterns, code: 403, message: "Forbidden", &block)
      raise ArgumentError, "block required" unless block

      validate_authorize_code!(code)

      opts = patterns.empty? ? {} : { only: patterns }
      use(**opts) do |request, next_call|
        raise Core::ApplicationError.new(code:, message:) unless block.call(request)

        next_call.call
      end
    end

    private

    def validate_authorize_code!(code)
      raise ArgumentError, "authorize code must be an Integer" unless code.is_a?(Integer)
      return unless code.between?(Core::RESERVED_ERROR_MIN, Core::RESERVED_ERROR_MAX)

      raise ArgumentError,
            "authorize code #{code} is in the reserved JSON-RPC range " \
            "(#{Core::RESERVED_ERROR_MIN}..#{Core::RESERVED_ERROR_MAX})"
    end
  end
  private_constant :ServerExtensions

  class Server
    include BatchProcessor
    include OpenRPCBuilder
    include ServerExtensions

    attr_reader :name, :version, :description, :max_batch_size, :timeout, :json_adapter

    HOOK_EVENTS = %i[request response error].freeze
    private_constant :HOOK_EVENTS

    def initialize(name: nil, version: nil, description: nil, max_batch_size: 100, expose_errors: false,
                   timeout: nil, concurrent_batches: false, max_concurrency: 8, json: JSON)
      @name = name
      @version = version
      @description = description
      @max_batch_size = max_batch_size
      @expose_errors = expose_errors
      @timeout = timeout
      @concurrent_batches = concurrent_batches
      @max_concurrency = max_concurrency
      @json = @json_adapter = json
      @handler = Core::Handler.new
      @middleware = []
      @hooks = HOOK_EVENTS.to_h { |e| [e, []] }
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil, returns: nil, deprecated: nil,
               params_schema: nil)
      @handler.expose(target, namespace:, only:, except:, descriptions:, returns:, deprecated:, params_schema:)
      self
    end

    def expose_method(name, callable = nil, description: nil, returns: nil, deprecated: nil, params_schema: nil, &)
      @handler.expose_method(name, callable, description:, returns:, deprecated:, params_schema:, &)
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
      data = @json.parse(json_string)
    rescue StandardError
      @json.generate(Core::Response.error(Core::PARSE_ERROR, nil))
    else
      handle_parsed(data)
    end

    alias call handle

    def handle_parsed(data)
      case data
      when Array then handle_batch(data)
      when Hash then serialize_single(data)
      else @json.generate(Core::Response.error(Core::INVALID_REQUEST, nil))
      end
    end

    def to_proc = method(:call).to_proc
    def inspect = "#<#{self.class}#{" name=#{@name.inspect}" if @name} methods=#{size} middleware=#{@middleware.size}>"
    def expose_errors? = @expose_errors
    def concurrent_batches? = @concurrent_batches

    def freeze
      @hooks.each_value(&:freeze)
      [@handler, @middleware, @hooks].each(&:freeze)
      @error_catalog&.each(&:freeze)
      @error_catalog&.freeze
      precompile_middleware
      super
    end

    def methods_list = @handler.methods_list
    def methods_info = @handler.methods_info
    def method?(method_name) = @handler.method?(method_name)
    def size = @handler.size
    def empty? = @handler.empty?

    private

    def serialize_single(data)
      request = parse_request(data)
      return request unless request.is_a?(Core::Request)

      response = execute_request(request)
      return nil unless response

      @json.generate(response)
    rescue StandardError
      return nil if request.is_a?(Core::Request) && request.notification?

      id = request.is_a?(Core::Request) ? request.id : extract_id(data)
      begin
        @json.generate(Core::Response.error(Core::INTERNAL_ERROR, id))
      rescue StandardError
        id_json = format_fallback_id(id)
        "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"},\"id\":#{id_json}}"
      end
    end

    def parse_request(data)
      Core::Request.new(data)
    rescue Core::InvalidRequest
      @json.generate(Core::Response.error(Core::INVALID_REQUEST, extract_id(data)))
    end

    def extract_id(data)
      return nil unless data.is_a?(Hash)

      data["id"].then { |id| id.nil? || id.is_a?(String) || id.is_a?(Numeric) ? id : nil }
    end

    def execute_request(request)
      emit(:request, request)
      result, error, _duration = timed_dispatch(request)
      error ? handle_dispatch_error(request:, error:) : handle_dispatch_success(request, result)
    end

    def timed_dispatch(request)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = with_timeout { build_chain(request).call }
      duration = elapsed(start)
      emit(:response, request, result, duration)
      [result, nil, duration]
    rescue StandardError => e
      duration = elapsed(start)
      emit(:error, request, e, duration)
      [nil, e, duration]
    end

    def handle_dispatch_success(request, result)
      request.notification? ? nil : Core::Response.success(result, request.id)
    end

    def handle_dispatch_error(request:, error:)
      return nil if request.notification?

      code, message, data = error_details(error)
      Core::Response.error(code, request.id, data: data, message: message)
    end

    def emit(event, *args)
      @hooks[event].each do |hook|
        hook.call(*args)
      rescue StandardError => e
        Kernel.warn "Reclamo: #{event} hook error: #{e.message}"
      end
    end

    def elapsed(start) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    def precompile_middleware
      methods = @handler.methods_list + ["rpc.discover"]
      @middleware_index = methods.to_h do |name|
        [name, @middleware.select { |_, matcher| matcher.call(name) }.freeze]
      end.freeze
    end

    def build_chain(request)
      applicable = @middleware_index&.[](request.method_name) ||
                   @middleware.select { |_, matcher| matcher.call(request.method_name) }
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

    def with_timeout(&)
      return yield unless @timeout

      Timeout.timeout(@timeout, &)
    rescue Timeout::Error
      raise Core::RequestTimeout
    end

    def invoke_handler(request)
      return @handler.call(request.method_name, request.params) unless request.method_name == "rpc.discover"

      build_openrpc_document
    end

    def error_details(err)
      case err
      when Core::MethodNotFound
        [Core::METHOD_NOT_FOUND, Core::ERROR_MESSAGES[Core::METHOD_NOT_FOUND], generic_data(err)]
      when Core::ApplicationError, Core::ServerError then [err.code, err.message, err.rpc_data]
      when Core::InvalidParams then [Core::INVALID_PARAMS, nil, generic_data(err, GENERIC_PARAMS_DATA)]
      when Core::InvalidRequest then [Core::INVALID_REQUEST, nil, generic_data(err)]
      else [Core::INTERNAL_ERROR, nil, generic_data(err)]
      end
    end

    def generic_data(err, fallback = GENERIC_ERROR_DATA) = @expose_errors ? err.message : fallback
  end
end
