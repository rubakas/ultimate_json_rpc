# frozen_string_literal: true

module Reclamo
  module Core
    # @api private
    VARIADIC_DEFAULTS = { rest: "args", keyrest: "kwargs" }.freeze
    private_constant :VARIADIC_DEFAULTS

    DANGEROUS_METHODS = %w[
      eval instance_eval class_eval module_eval
      send public_send __send__
      system exec spawn fork
      define_method remove_method undef_method
      binding method_missing respond_to_missing?
      exit exit! abort
      require require_relative load
      open
      instance_variable_get instance_variable_set
      class_variable_get class_variable_set
      const_get const_set remove_const
      method
      include extend prepend
      attr_accessor attr_reader attr_writer
      public private protected
    ].freeze
    private_constant :DANGEROUS_METHODS

    TYPE_CHECKS = {
      "string" => String, "number" => Numeric, "integer" => Integer,
      "boolean" => [TrueClass, FalseClass], "array" => Array,
      "object" => Hash, "null" => NilClass
    }.freeze
    private_constant :TYPE_CHECKS

    JSON_TYPE_NAMES = {
      String => "string", Integer => "integer", Float => "number",
      TrueClass => "boolean", FalseClass => "boolean",
      Array => "array", Hash => "object", NilClass => "null"
    }.freeze
    private_constant :JSON_TYPE_NAMES

    PARAM_FLAGS = {
      req: { "required" => true }, keyreq: { "required" => true, "keyword" => true },
      opt: {}, key: { "keyword" => true },
      rest: { "variadic" => true }, keyrest: { "variadic" => true, "keyword" => true }
    }.freeze
    private_constant :PARAM_FLAGS

    module ParamValidator
      private

      def validate_params!(callable, params, schema)
        return unless schema

        case params
        when Array then validate_positional!(callable, params, schema)
        when Hash then validate_keyword!(params, schema)
        end
      end

      def validate_positional!(callable, params, schema)
        names = callable.parameters.filter_map { |type, pname| pname&.to_s unless type == :block }
        params.each_with_index do |value, index|
          validate_value!(names[index], value, schema[names[index]]) if names[index] && schema[names[index]]
        end
      end

      def validate_keyword!(params, schema)
        params.each { |k, v| validate_value!(k.to_s, v, schema[k.to_s]) if schema.key?(k.to_s) }
      end

      def validate_value!(name, value, pschema)
        check_param_type!(name, value, pschema)
        check_param_enum!(name, value, pschema)
      end

      def check_param_type!(name, value, pschema)
        type = pschema["type"]
        return unless type

        expected = TYPE_CHECKS[type]
        return unless expected
        return unless Array(expected).none? { |k| value.is_a?(k) }

        raise InvalidParams, "parameter '#{name}' must be #{type}, " \
                             "got #{JSON_TYPE_NAMES.fetch(value.class, value.class.name)}"
      end

      def check_param_enum!(name, value, pschema)
        return unless (enum = pschema["enum"]) && !enum.include?(value)

        raise InvalidParams, "parameter '#{name}' must be one of: #{enum.map(&:inspect).join(", ")}"
      end
    end
    private_constant :ParamValidator

    class Handler
      include ParamValidator

      Entry = Struct.new(:callable, :description, :returns, :deprecated, :params_schema)
      private_constant :Entry

      def initialize
        @entries = {}
      end

      def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil, returns: nil, deprecated: nil,
                 params_schema: nil)
        validate_expose_args!(target, only, except)
        prefix = namespace.to_s.then { |ns| ns.empty? ? "" : "#{ns}." }
        methods = filter_methods(callable_methods(target), only: only, except: except)
        Kernel.warn "Reclamo: expose registered 0 methods from #{target.inspect}" if methods.empty?
        methods.each do |m|
          register_exposed(prefix:, method_name: m, target:, descriptions:, returns:, deprecated:, params_schema:)
        end
      end

      def expose_method(name, callable = nil, description: nil, returns: nil, deprecated: nil, params_schema: nil,
                        &block)
        callable = resolve_callable(callable, block)
        name = name.to_s
        validate_method_name!(name)
        @entries[name] = Entry.new(
          callable: callable,
          description: description&.to_s,
          returns: returns,
          deprecated: normalize_deprecated(deprecated),
          params_schema: params_schema&.transform_keys(&:to_s)
        )
      end

      def call(method_name, params)
        entry = @entries[method_name]
        raise MethodNotFound, method_name unless entry

        validate_params!(entry.callable, params, entry.params_schema)
        invoke_callable(entry.callable, params)
      end

      def method?(method_name) = @entries.key?(method_name)
      def methods_list = @entries.keys.sort
      def methods_info = @entries.keys.sort.map { |name| method_info(name) }
      def size = @entries.size
      def empty? = @entries.empty?

      def freeze
        @entries.each_value(&:freeze)
        @entries.freeze
        super
      end

      private

      def method_info(name)
        entry = @entries[name]
        info = { "name" => name }
        add_method_metadata(info:, entry:)
        info
      end

      def add_method_metadata(info:, entry:)
        info["description"] = entry.description if entry.description
        add_params(info:, entry:)
        info["result"] = build_result(entry.returns) if entry.returns
        info["deprecated"] = entry.deprecated if entry.deprecated
      end

      def add_params(info:, entry:)
        schema = entry.params_schema
        params = entry.callable.parameters.filter_map { |type, pname| param_descriptor(type:, pname:, schema:) }
        info["params"] = params unless params.empty?
      end

      def build_result(returns)
        case returns
        when Hash then { "name" => "result" }.merge(returns)
        when String then { "name" => "result", "schema" => { "type" => returns } }
        else { "name" => "result", "schema" => returns }
        end
      end

      def param_descriptor(type:, pname:, schema:)
        return if type == :block

        name = pname&.to_s || VARIADIC_DEFAULTS.fetch(type, "arg")
        desc = { "name" => name }.merge(PARAM_FLAGS.fetch(type, {}))
        desc["schema"] = schema[name] if schema&.key?(name)
        desc
      end

      def register_exposed(prefix:, method_name:, target:, descriptions:, returns:, deprecated:, params_schema:)
        full_name = "#{prefix}#{method_name}"
        validate_method_name!(full_name)
        @entries[full_name] = Entry.new(
          callable: target.method(method_name.to_sym),
          description: extract_metadata(descriptions, method_name)&.to_s,
          returns: extract_metadata(returns, method_name),
          deprecated: normalize_deprecated(extract_metadata(deprecated, method_name)),
          params_schema: extract_metadata(params_schema, method_name)&.then { |v| v.transform_keys(&:to_s) }
        )
      end

      def normalize_deprecated(value)
        return nil unless value

        value == true ? true : value.to_s
      end

      def extract_metadata(source, method_name)
        return nil unless source.is_a?(Hash)

        sym_key = method_name.to_sym
        return source[sym_key] if source.key?(sym_key)

        source[method_name.to_s]
      end

      def callable_methods(target)
        if target.is_a?(Module)
          target.singleton_methods(false).map(&:to_s)
        else
          ((target.class.public_instance_methods(false) - Object.public_instance_methods) |
           target.singleton_methods(false)).map(&:to_s)
        end
      end

      def filter_methods(methods, only:, except:)
        if only
          allowed = Array(only).map(&:to_s)
          methods.select { |m| allowed.include?(m) }
        elsif except
          blocked = Array(except).map(&:to_s)
          methods.reject { |m| blocked.include?(m) }
        else
          methods
        end
      end

      def validate_expose_args!(target, only, except)
        raise ArgumentError, "target must not be nil" if target.nil?
        raise ArgumentError, "cannot use both :only and :except" if only && except
      end

      def validate_method_name!(name)
        raise ArgumentError, "method name must not be empty" if name.empty?
        raise ArgumentError, "method names starting with 'rpc.' are reserved" if name.start_with?("rpc.")

        validate_segments!(name)
        raise ArgumentError, "method '#{name}' is already registered" if @entries.key?(name)
      end

      def validate_segments!(name)
        segments = name.include?(".") ? name.split(".", -1) : [name]
        segments.each do |segment|
          raise ArgumentError, "method name contains empty segment" if segment.empty?
          raise ArgumentError, "method name '#{segment}' is dangerous" if DANGEROUS_METHODS.include?(segment)
        end
      end

      def resolve_callable(callable, block)
        raise ArgumentError, "provide either a callable or a block, not both" if callable && block
        raise ArgumentError, "a callable or block is required" unless callable || block

        (callable || block).tap do |resolved|
          raise ArgumentError, "callable must respond to #call" unless resolved.respond_to?(:call)
        end
      end

      def invoke_callable(callable, params)
        case params
        when Array then callable.call(*params)
        when Hash  then callable.call(**safe_symbolize_keys(callable, params))
        when nil   then callable.call
        else raise ArgumentError, "params must be an Array, Hash, or nil"
        end
      end

      def safe_symbolize_keys(callable, params)
        return params.transform_keys(&:to_sym) if accepts_keyrest?(callable)

        known = known_keyword_params(callable)
        params.each_with_object({}) do |(k, v), h|
          key = k.to_s
          raise ArgumentError, "unknown keyword: #{key}" unless known.key?(key)

          h[known[key]] = v
        end
      end

      def known_keyword_params(callable)
        callable.parameters.each_with_object({}) do |(type, name), map|
          map[name.to_s] = name if name && %i[key keyreq].include?(type)
        end
      end

      def accepts_keyrest?(callable)
        callable.parameters.any? { |type, _| type == :keyrest }
      end
    end
  end
end
