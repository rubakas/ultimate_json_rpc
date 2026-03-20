# frozen_string_literal: true

module UltimateJsonRpc
  module Extras
    class RateLimiter
      def initialize(server, max:, period:, key: nil, code: 429, message: "Rate limit exceeded", only: nil, except: nil)
        validate_code!(code)
        @max = max
        @period = period
        @key_fn = build_key_fn(key)
        @code = code
        @message = message
        @windows = {}
        @mutex = Mutex.new
        server.use(only:, except:) do |request, next_call|
          check!(@key_fn.call(request))
          next_call.call
        end
      end

      private

      def build_key_fn(key)
        case key
        when nil then ->(_) { :global }
        when Symbol then ->(req) { req.context.fetch(key, :unknown) }
        when Proc then key
        else raise ArgumentError, "key must be nil, a Symbol, or a Proc"
        end
      end

      def check!(bucket)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @mutex.synchronize do
          window = (@windows[bucket] ||= [])
          window.reject! { |t| now - t > @period }
          raise Core::ApplicationError.new(code: @code, message: @message) if window.size >= @max

          window << now
          evict_stale!(now)
        end
      end

      def evict_stale!(now)
        @windows.delete_if { |_, w| w.none? { |t| now - t <= @period } } if @windows.size > 20
      end

      def validate_code!(code)
        raise ArgumentError, "code must be an Integer" unless code.is_a?(Integer)
        return unless code.between?(Core::RESERVED_ERROR_MIN, Core::RESERVED_ERROR_MAX)

        raise ArgumentError,
              "code #{code} is in the reserved JSON-RPC range (#{Core::RESERVED_ERROR_MIN}..#{Core::RESERVED_ERROR_MAX})"
      end
    end
  end
end
