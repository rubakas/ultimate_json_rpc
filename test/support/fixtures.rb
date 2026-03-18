# frozen_string_literal: true

module Calculator
  def self.add(left, right)
    left + right
  end

  def self.divide(numerator, denominator)
    raise ZeroDivisionError, "division by zero" if denominator.zero?

    numerator.to_f / denominator
  end
end

class Greeter
  def initialize(greeting)
    @greeting = greeting
  end

  def greet(name:)
    "#{@greeting}, #{name}!"
  end

  def hello
    "hello"
  end
end
