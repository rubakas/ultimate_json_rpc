# frozen_string_literal: true

module Reclamo
  module Extras
    module Logging
      def log_to(logger, level: :info)
        on(:response) do |request, _result, duration|
          logger.public_send(level, "Reclamo") { "#{request.method_name} (#{format("%.1f", duration * 1000)}ms)" }
        end

        on(:error) do |request, error, duration|
          logger.error("Reclamo") { "#{request.method_name} #{error.class} (#{format("%.1f", duration * 1000)}ms)" }
        end

        self
      end
    end
  end

  # Intentional load-time patching: adds log_to to Server when reclamo/extras/logging is required.
  Server.include(Extras::Logging)
end
