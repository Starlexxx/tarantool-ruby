# frozen_string_literal: true

require 'minitest'

# Runs ActiveModel::Lint::Tests (minitest assertions) from RSpec examples.
class Lint
  include Minitest::Assertions
  include ActiveModel::Lint::Tests

  attr_accessor :assertions

  def self.tests = ActiveModel::Lint::Tests.public_instance_methods.grep(/\Atest_/)

  def initialize(model)
    @model = model
    @assertions = 0
  end
end
