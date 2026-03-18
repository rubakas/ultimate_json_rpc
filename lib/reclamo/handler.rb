# frozen_string_literal: true

module Reclamo
  class Handler
    def initialize
      @targets = {}
    end

    def expose(target, namespace: nil)
      prefix = namespace ? "#{namespace}." : ""
      methods = callable_methods(target)
      methods.each do |method_name|
        @targets["#{prefix}#{method_name}"] = [target, method_name]
      end
    end

    def call(method_name, params)
      entry = @targets[method_name]
      raise MethodNotFound, method_name unless entry

      target, meth = entry
      invoke(target, meth, params)
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

    def invoke(target, method_name, params)
      callable = target.method(method_name.to_sym)

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
