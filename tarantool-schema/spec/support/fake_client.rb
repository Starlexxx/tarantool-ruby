# frozen_string_literal: true

# Answers Inspector evals from a Hash of raw space descriptions keyed by name and records every eval.
# The on_create block runs after each other eval, so a spec can make created objects appear.
# masks: privilege masks by space and grantee name; users: every known user or role, nil means all exist.
class FakeClient
  READS = [Tarantool::Schema::Inspector::LUA, Tarantool::Schema::SpaceLister::LUA,
           Tarantool::Schema::GrantInspector::LUA].freeze

  attr_reader :evals, :live, :masks
  attr_accessor :users

  def initialize(live = {})
    @live = live
    @masks = {}
    @evals = []
  end

  def on_create(&block)
    @on_create = block
  end

  def eval(expression, arguments = [])
    @evals << [expression, arguments]
    return [@live[arguments.first]] if expression == Tarantool::Schema::Inspector::LUA
    return [@live.keys] if expression == Tarantool::Schema::SpaceLister::LUA
    return [grants_answer(*arguments)] if expression == Tarantool::Schema::GrantInspector::LUA

    @on_create&.call(self)

    []
  end

  def creations
    @evals.reject { |evaluation| READS.include?(evaluation.first) }
  end

  private

  def grants_answer(space, grantees)
    { 'masks' => @masks.fetch(space, {}), 'missing' => @users ? grantees - @users : [] }
  end
end
