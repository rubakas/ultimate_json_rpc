# frozen_string_literal: true

module DiscoverHelper
  private

  def discover_result(server)
    request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))["result"]
  end

  def discover_methods(server)
    discover_result(server)["methods"]
  end
end
