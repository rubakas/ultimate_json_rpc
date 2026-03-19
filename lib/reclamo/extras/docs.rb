# frozen_string_literal: true

module Reclamo
  module Extras
    class Docs
      def initialize(server, json: JSON)
        @server = server
        @json = json
      end

      def to_markdown
        lines = []
        lines << title_section
        lines << methods_section
        lines << errors_section
        lines.compact.join("\n")
      end

      private

      def discover
        @discover ||= begin
          request = { "jsonrpc" => "2.0", "method" => "rpc.discover", "id" => 1 }
          result = @json.parse(@server.handle(@json.generate(request)))
          raise "rpc.discover returned an error: #{result["error"]&.inspect}" unless result.key?("result")

          result["result"]
        end
      end

      def title_section
        info = discover["info"]
        return "# API Reference\n" unless info

        lines = []
        lines << "# #{info["title"] || "API Reference"}\n"
        lines << "#{info["description"]}\n" if info["description"]
        lines << "**Version:** #{info["version"]}\n" if info["version"]
        lines.join("\n")
      end

      def methods_section
        methods = discover["methods"]
        return nil if methods.nil? || methods.empty?

        lines = ["## Methods\n"]
        methods.each { |m| lines << method_entry(m) }
        lines.join("\n")
      end

      def method_entry(method)
        lines = ["### `#{method["name"]}`\n"]
        append_method_metadata(lines, method)
        lines.join("\n")
      end

      def append_method_metadata(lines, method)
        lines << "#{method["description"]}\n" if method["description"]
        lines << "*Deprecated: #{deprecation_text(method["deprecated"])}*\n" if method["deprecated"]
        lines << params_table(method["params"]) if method["params"]&.any?
        lines << return_section(method["result"]) if method["result"]
      end

      def deprecation_text(value)
        value == true ? "This method is deprecated." : value.to_s
      end

      def params_table(params)
        lines = ["**Parameters:**\n"]
        lines << "| Name | Required | Type |"
        lines << "|------|----------|------|"
        params.each do |p|
          required = p["required"] ? "Yes" : "No"
          type = escape_cell(p.dig("schema", "type") || "-")
          lines << "| `#{escape_cell(p["name"])}` | #{required} | #{type} |"
        end
        lines << ""
        lines.join("\n")
      end

      def return_section(result)
        type = result["type"] || result.dig("schema", "type")
        return nil unless type

        "**Returns:** `#{type}`\n"
      end

      def escape_cell(text)
        text.to_s.gsub("|", "\\|")
      end

      def errors_section
        errors = discover.dig("components", "errors")
        return nil unless errors&.any?

        lines = ["## Error Codes\n"]
        lines << "| Code | Name | Description |"
        lines << "|------|------|-------------|"
        errors.each do |e|
          lines << "| #{e["code"]} | #{escape_cell(e["message"])} | #{escape_cell(e["data"] || "-")} |"
        end
        lines << ""
        lines.join("\n")
      end
    end
  end
end
