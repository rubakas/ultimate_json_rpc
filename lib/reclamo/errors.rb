# frozen_string_literal: true

module Reclamo
  PARSE_ERROR = -32_700
  INVALID_REQUEST = -32_600
  METHOD_NOT_FOUND = -32_601
  INVALID_PARAMS = -32_602
  INTERNAL_ERROR = -32_603

  # Implementation-defined server error range (-32000 to -32099)
  SERVER_ERROR_MIN = -32_099
  SERVER_ERROR_MAX = -32_000

  ERROR_MESSAGES = {
    PARSE_ERROR => "Parse error",
    INVALID_REQUEST => "Invalid Request",
    METHOD_NOT_FOUND => "Method not found",
    INVALID_PARAMS => "Invalid params",
    INTERNAL_ERROR => "Internal error"
  }.freeze

  # Reserved range for JSON-RPC protocol errors (-32768 to -32000)
  RESERVED_ERROR_MIN = -32_768
  RESERVED_ERROR_MAX = -32_000

  class InvalidRequest < Error; end
  class InvalidParams < Error; end

  class MethodNotFound < Error
    attr_reader :method_name

    def initialize(method_name)
      @method_name = method_name
      super("Method not found: #{method_name}")
    end
  end

  class ApplicationError < Error
    attr_reader :code, :rpc_data

    def initialize(code, message, data = nil)
      raise ArgumentError, "error code must be an Integer, got #{code.class}" unless code.is_a?(Integer)

      if code.between?(RESERVED_ERROR_MIN, RESERVED_ERROR_MAX)
        hint = code.between?(SERVER_ERROR_MIN, SERVER_ERROR_MAX) ? "; use ServerError for server error codes" : ""
        raise ArgumentError,
              "error code #{code} is in the reserved range (#{RESERVED_ERROR_MIN}..#{RESERVED_ERROR_MAX})#{hint}"
      end

      @code = code
      @rpc_data = data
      super(message)
    end
  end

  class ServerError < Error
    attr_reader :code, :rpc_data

    def initialize(code, message, data = nil)
      unless code.is_a?(Integer) && code.between?(SERVER_ERROR_MIN, SERVER_ERROR_MAX)
        raise ArgumentError,
              "server error code must be in range (#{SERVER_ERROR_MIN}..#{SERVER_ERROR_MAX}), got #{code}"
      end

      @code = code
      @rpc_data = data
      super(message)
    end
  end

  REQUEST_TIMEOUT = -32_001

  class RequestTimeout < ServerError
    def initialize(_message = nil)
      super(REQUEST_TIMEOUT, "Request timeout")
    end
  end
end
