# frozen_string_literal: true

module Reclamo
  class Recorder
    attr_reader :exchanges

    def initialize(server, output: nil)
      @exchanges = []
      @output = output
      @mutex = Mutex.new
      attach(server)
    end

    def clear
      @mutex.synchronize { @exchanges.clear }
    end

    def size = @exchanges.size

    private

    def attach(server)
      server.on(:response) do |request, result, duration|
        record(request, duration, result:)
      end

      server.on(:error) do |request, error, duration|
        record(request, duration, error: { "class" => error.class.name, "message" => error.message })
      end
    end

    def record(request, duration, result: nil, error: nil)
      entry = { "method" => request.method_name, "params" => request.params,
                "duration" => duration.round(6) }
      entry["result"] = result if result
      entry["error"] = error if error
      @mutex.synchronize do
        @exchanges << entry
        @output&.puts(JSON.generate(entry))
      end
    end
  end
end
