# frozen_string_literal: true

require "socket"

module Reclamo
  class TCP
    def initialize(server, port:, host: "127.0.0.1")
      @server = server
      @host = host
      @port = port
      @running = false
      @tcp_server = nil
    end

    def run
      @running = true
      @tcp_server = TCPServer.new(@host, @port)
      trap_signals
      accept_loop
    ensure
      @running = false
      @tcp_server&.close unless @tcp_server&.closed?
    end

    def stop
      @running = false
      @tcp_server&.close unless @tcp_server&.closed?
    end

    def running? = @running

    private

    def accept_loop
      while @running
        client = begin
          @tcp_server.accept
        rescue IOError
          break
        end
        next unless client

        Thread.new(client) { |c| handle_client(c) }
      end
    end

    def handle_client(client)
      client.each_line do |line|
        line = line.chomp
        next if line.empty?

        response = @server.handle(line)
        next unless response

        client.puts(response)
        client.flush
      end
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      # Client disconnected
    ensure
      client.close unless client.closed?
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { stop }
      rescue ArgumentError
        # Signal not supported on this platform
      end
    end
  end
end
