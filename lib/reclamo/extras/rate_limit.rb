# frozen_string_literal: true

module Reclamo
  module Extras
    class RateLimiter
      def initialize(max:, period:, key: nil, code: 429, message: "Rate limit exceeded")
        validate_code!(code)
        @max = max
        @period = period
        @key_fn = build_key_fn(key)
        @code = code
        @message = message
        @windows = {}
        @mutex = Mutex.new
      end

      def call(request, next_call)
        check!(@key_fn.call(request))
        next_call.call
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

    module RateLimitSupport
      def rate_limit(max:, period:, key: nil, code: 429, message: "Rate limit exceeded", only: nil, except: nil)
        limiter = RateLimiter.new(max:, period:, key:, code:, message:)
        use(only:, except:) { |request, next_call| limiter.call(request, next_call) }
      end
    end
  end

  # Intentional load-time patching: adds rate_limit to Server when reclamo/rate_limit is required.
  Server.include(Extras::RateLimitSupport)
end
