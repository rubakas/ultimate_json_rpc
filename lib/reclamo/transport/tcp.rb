# frozen_string_literal: true

require "socket"

module Reclamo
  module Transport
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
        @client_threads = []
        @mutex = Mutex.new
      end

      MAX_LINE_BYTES = 4 * 1024 * 1024

      def run
        @mutex.synchronize do
          @running = true
          @tcp_server = TCPServer.new(@host, @port)
        end
        trap_signals
        accept_loop
      ensure
        @mutex.synchronize { @running = false }
        close_server
      end

      def stop
        @mutex.synchronize { @running = false }
        close_server
        threads = @mutex.synchronize { @client_threads.dup }
        threads.each do |t|
          t.join(5)
          t.kill if t.alive?
        end
        @mutex.synchronize do
          @client_threads.clear
          @connection_count = 0
        end
      end

      def running? = @mutex.synchronize { @running }

      def port
        server = @mutex.synchronize { @tcp_server }
        server&.addr&.[](1)
      end

      private

      def accept_loop
        while (server = @mutex.synchronize { @running && @tcp_server })
          next unless server.wait_readable(0.5)

          client = accept_client(server)
          next unless client

          accept_or_reject(client)
        end
      rescue Errno::EBADF, IOError
        # Server socket was closed (e.g., via stop)
      end

      def accept_client(server)
        server.accept
      rescue IOError, Errno::EBADF, Errno::EMFILE, Errno::ENFILE, Errno::ECONNABORTED
        nil
      end

      def accept_or_reject(client)
        if acquire_connection_slot
          begin
            thread = Thread.new(client) { |c| handle_client(c) }
            @mutex.synchronize { @client_threads << thread }
          rescue ThreadError
            client.close rescue nil # rubocop:disable Style/RescueModifier
            decrement_connections
          end
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
        while (line = client.gets("\n", MAX_LINE_BYTES))
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
        @mutex.synchronize do
          @connection_count -= 1
          @client_threads.delete(Thread.current)
        end
      end

      def close_server
        server = @mutex.synchronize do
          s = @tcp_server
          @tcp_server = nil
          s
        end
        server&.close
      rescue IOError, Errno::EBADF
        # Already closed
      end

      def trap_signals
        # Signal handlers set @running directly (no mutex). This is safe on MRI
        # where boolean assignment is atomic. The accept_loop checks
        # @running via mutex on each iteration, picking up the change.
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { @running = false }
        rescue ArgumentError
          # Signal not supported on this platform
        end
      end
    end
  end
end
