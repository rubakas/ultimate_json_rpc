# frozen_string_literal: true

module Reclamo
  class Recorder
    UNSET = Object.new.freeze
    private_constant :UNSET

    def initialize(server, output: nil, max_exchanges: nil, json: JSON)
      @exchanges = []
      @max_exchanges = max_exchanges
      @output = output
      @json = json
      @mutex = Mutex.new
      @output_mutex = Mutex.new
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
        @exchanges.shift if @max_exchanges && @exchanges.size > @max_exchanges
      end
      write_output(entry)
    end

    def write_output(entry)
      return unless @output

      @output_mutex.synchronize do
        @output.puts(@json.generate(entry))
        @output.flush
      end
    rescue IOError, SystemCallError
      # Output broken; exchange still recorded in memory
    end
  end
end
