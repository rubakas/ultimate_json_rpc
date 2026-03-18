# frozen_string_literal: true

module Reclamo
  class Rack
    CONTENT_TYPE = { "content-type" => "application/json" }.freeze
    ALLOWED_METHODS = %w[POST].freeze

    def initialize(server)
      @server = server
    end

    def call(env)
      return method_not_allowed unless ALLOWED_METHODS.include?(env["REQUEST_METHOD"])

      body = env["rack.input"]&.read.to_s
      response = @server.handle(body)

      if response
        [200, CONTENT_TYPE, [response]]
      else
        [204, {}, []]
      end
    end

    def freeze
      @server.freeze
      super
    end

    private

    def method_not_allowed
      [405, CONTENT_TYPE.merge("allow" => "POST"), ['{"error":"Method Not Allowed"}']]
    end
  end
end
