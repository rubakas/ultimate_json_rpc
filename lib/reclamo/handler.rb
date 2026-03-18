# frozen_string_literal: true

module Reclamo
  class Handler
    def initialize
      @targets = {}
    end

    def expose(target, namespace: nil, only: nil, except: nil)
      raise ArgumentError, "cannot use both :only and :except" if only && except

      prefix = namespace ? "#{namespace}." : ""
      methods = callable_methods(target)
      methods = filter_methods(methods, only: only, except: except)
      methods.each do |method_name|
        full_name = "#{prefix}#{method_name}"
        validate_method_name!(full_name)
        check_duplicate!(full_name)
        @targets[full_name] = [target, method_name]
      end
    end

    def expose_method(name, &block)
      raise ArgumentError, "block required" unless block

      validate_method_name!(name)
      check_duplicate!(name)
      @targets[name] = block
    end

    def call(method_name, params)
      entry = @targets[method_name]
      raise MethodNotFound, method_name unless entry

      if entry.is_a?(Array)
        target, meth = entry
        invoke(target, meth, params)
      else
        invoke_callable(entry, params)
      end
    end

    def method?(method_name)
      @targets.key?(method_name)
    end

    def methods_list
      @targets.keys.sort
    end

    private

    def callable_methods(target)
      case target
      when Module
        (target.public_methods(false) - Module.public_instance_methods).map(&:to_s)
      else
        (target.public_methods(false) - Object.public_instance_methods).map(&:to_s)
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

    def validate_method_name!(name)
      raise ArgumentError, "method names starting with 'rpc.' are reserved" if name.start_with?("rpc.")
    end

    def check_duplicate!(name)
      raise ArgumentError, "method '#{name}' is already registered" if @targets.key?(name)
    end

    def invoke(target, method_name, params)
      callable = target.method(method_name.to_sym)
      invoke_callable(callable, params)
    end

    def invoke_callable(callable, params)
      case params
      when Array
        callable.call(*params)
      when Hash
        kwargs = params.transform_keys(&:to_sym)
        callable.call(**kwargs)
      when nil
        callable.call
      end
    end
  end

  class MethodNotFound < Error; end
end
