# frozen_string_literal: true

module Reclamo
  class Recorder
    def initialize(server, output: nil, json: JSON)
      @exchanges = []
      @output = output
      @json = json
      @mutex = Mutex.new
      attach(server)
    end

    def exchanges
      @mutex.synchronize { @exchanges.dup }
    end

    def clear
      @mutex.synchronize { @exchanges.clear }
    end

    def size
      @mutex.synchronize { @exchanges.size }
    end

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
        @output&.puts(@json.generate(entry))
      end
    end
  end
end
