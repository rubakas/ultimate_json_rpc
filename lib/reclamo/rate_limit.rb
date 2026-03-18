# frozen_string_literal: true

module Reclamo
  class RateLimiter
    def initialize(max:, period:, key: nil, code: 429, message: "Rate limit exceeded")
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
      when Symbol then ->(req) { req.context[key] || :unknown }
      when Proc then key
      else raise ArgumentError, "key must be nil, a Symbol, or a Proc"
      end
    end

    def check!(bucket)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @mutex.synchronize do
        window = (@windows[bucket] ||= [])
        window.reject! { |t| now - t > @period }
        raise ApplicationError.new(@code, @message) if window.size >= @max

        window << now
      end
    end
  end

  module RateLimitSupport
    def rate_limit(max:, period:, key: nil, code: 429, message: "Rate limit exceeded", only: nil, except: nil)
      limiter = RateLimiter.new(max:, period:, key:, code:, message:)
      use(only:, except:) { |request, next_call| limiter.call(request, next_call) }
    end
  end

  Server.include(RateLimitSupport)
end
