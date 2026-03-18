# frozen_string_literal: true

module Reclamo
  class Stdio
    def initialize(server, input: $stdin, output: $stdout)
      @server = server
      @input = input
      @output = output
      @running = false
    end

    def run
      @running = true
      trap_signals
      process_lines
    ensure
      @running = false
    end

    def stop
      @running = false
    end

    def running? = @running

    private

    def process_lines
      @input.each_line do |line|
        break unless @running

        line = line.chomp
        next if line.empty?

        response = @server.handle(line)
        next unless response

        @output.puts(response)
        @output.flush
      end
    end

    def trap_signals
      # Signal handlers set @running directly (no mutex). This is safe on MRI
      # where boolean assignment is atomic. The process_lines loop checks
      # @running between lines via each_line.
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @running = false }
      rescue ArgumentError
        # Signal not supported on this platform
      end
    end
  end
end
