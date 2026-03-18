# frozen_string_literal: true

require "socket"

module Reclamo
  # TCP adapter for Reclamo servers.
  # Thread-safety: each client gets its own thread. The @connection_count counter is protected
  # by a Mutex. Under CRuby's GVL, Array/Hash reads are safe, but the Mutex ensures correctness
  # on alternative Ruby implementations as well.
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
      close_server
    end

    def stop
      @running = false
      close_server
    end

    def running? = @running

    private

    def accept_loop
      while @running
        next unless @tcp_server.wait_readable(0.5)

        client = accept_client
        break unless client

        accept_or_reject(client)
      end
    rescue Errno::EBADF, IOError
      # Server socket was closed (e.g., via stop)
    end

    def accept_client
      @tcp_server.accept
    rescue IOError, Errno::EBADF
      nil
    end

    def accept_or_reject(client)
      if acquire_connection_slot
        Thread.new(client) { |c| handle_client(c) }
      else
        client.close
      end
    end

    def acquire_connection_slot
      @mutex.synchronize do
        return false if @connection_count >= @max_connections

        @connection_count += 1
        true
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

    def decrement_connections
      @mutex.synchronize { @connection_count -= 1 }
    end

    def close_server
      @tcp_server&.close
    rescue IOError, Errno::EBADF
      # Already closed
    end

    def trap_signals
      # Signal handlers must not perform I/O; only set the flag.
      # The accept_loop uses IO.select with a timeout to notice the change.
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @running = false }
      rescue ArgumentError
        # Signal not supported on this platform
      end
    end
  end
end
