# frozen_string_literal: true

# Answers Inspector evals from a Hash of raw space descriptions keyed by name and records every eval.
# The on_create block runs after each other eval, so a spec can make created objects appear.
class FakeClient
  attr_reader :evals, :live

  def initialize(live = {})
    @live = live
    @evals = []
  end

  def on_create(&block)
    @on_create = block
  end

  def eval(expression, arguments = [])
    @evals << [expression, arguments]
    return [@live[arguments.first]] if expression == Tarantool::Schema::Inspector::LUA

    @on_create&.call(self)

    []
  end

  def creations
    @evals.reject { |expression, _| expression == Tarantool::Schema::Inspector::LUA }
  end
end
