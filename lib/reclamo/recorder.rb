# frozen_string_literal: true

module Reclamo
  class Recorder
    UNSET = Object.new.freeze
    private_constant :UNSET

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

    def record(request, duration, result: UNSET, error: nil)
      entry = { "method" => request.method_name, "params" => request.params,
                "duration" => duration.round(6) }
      entry["result"] = result unless result.equal?(UNSET)
      entry["error"] = error if error
      @mutex.synchronize do
        @exchanges << entry
        @output&.puts(@json.generate(entry))
      end
    end
  end
end
