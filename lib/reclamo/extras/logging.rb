# frozen_string_literal: true

module Reclamo
  module Extras
    class Logging
      def initialize(server, logger, level: :info)
        server.on(:response) do |request, _result, duration|
          logger.public_send(level, "Reclamo") { "#{request.method_name} (#{format("%.1f", duration * 1000)}ms)" }
        end

        server.on(:error) do |request, error, duration|
          logger.error("Reclamo") { "#{request.method_name} #{error.class} (#{format("%.1f", duration * 1000)}ms)" }
        end
      end
    end
  end
end
