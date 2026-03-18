# frozen_string_literal: true

module Reclamo
  module TestHelpers
    def rpc_call(server, method, params: nil, id: 1)
      request = { "jsonrpc" => "2.0", "method" => method, "id" => id }
      request["params"] = params if params
      JSON.parse(server.handle(JSON.generate(request)))
    end

    def rpc_notify(server, method, params: nil)
      request = { "jsonrpc" => "2.0", "method" => method }
      request["params"] = params if params
      server.handle(JSON.generate(request))
    end

    def rpc_batch(server, *requests)
      result = server.handle(JSON.generate(requests))
      result ? JSON.parse(result) : nil
    end
  end
end
