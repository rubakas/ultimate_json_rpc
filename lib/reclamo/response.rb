# frozen_string_literal: true

module Reclamo
  module Response
    def self.success(result, id)
      {
        "jsonrpc" => "2.0",
        "result" => result,
        "id" => id
      }
    end

    def self.error(code, id, data: nil, message: nil)
      err = {
        "code" => code,
        "message" => message || ERROR_MESSAGES.fetch(code, "Unknown error")
      }
      err["data"] = data if data
      {
        "jsonrpc" => "2.0",
        "error" => err,
        "id" => id
      }
    end
  end
end
