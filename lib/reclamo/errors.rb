# frozen_string_literal: true

module Reclamo
  PARSE_ERROR = -32_700
  INVALID_REQUEST = -32_600
  METHOD_NOT_FOUND = -32_601
  INVALID_PARAMS = -32_602
  INTERNAL_ERROR = -32_603

  ERROR_MESSAGES = {
    PARSE_ERROR => "Parse error",
    INVALID_REQUEST => "Invalid Request",
    METHOD_NOT_FOUND => "Method not found",
    INVALID_PARAMS => "Invalid params",
    INTERNAL_ERROR => "Internal error"
  }.freeze
end
