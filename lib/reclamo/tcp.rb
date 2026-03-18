# frozen_string_literal: true

require "socket"

module Reclamo
  class TCP
    DEFAULT_MAX_CONNECTIONS = 64

    def initialize(server, port:, host: "127.0.0.1", max_connections: DEFAULT_MAX_CONNECTIONS)
      @server = server
      @host = host
      @port = port
      @max_connections = max_connections
      @running = false
      @tcp_server = nil
      @connection_count = 0
      @mutex = Mutex.new
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
        client = accept_client
        break unless client

        accept_or_reject(client)
      end
    end

    def accept_client
      @tcp_server.accept
    rescue IOError
      nil
    end

    def accept_or_reject(client)
      if connection_limit_reached?
        client.close
      else
        increment_connections
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
      decrement_connections
    end

    def connection_limit_reached?
      @mutex.synchronize { @connection_count >= @max_connections }
    end

    def increment_connections
      @mutex.synchronize { @connection_count += 1 }
    end

    def decrement_connections
      @mutex.synchronize { @connection_count -= 1 }
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
