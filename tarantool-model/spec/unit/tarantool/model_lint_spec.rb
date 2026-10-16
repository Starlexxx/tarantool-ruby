# frozen_string_literal: true

RSpec.describe Tarantool::Model do
  let(:model) do
    Class.new do
      include Tarantool::Model

      attribute :id, :integer

      def self.name = 'Linted'
    end
  end

  Lint.tests.each do |test|
    it(test.to_s.delete_prefix('test_').tr('_', ' ')) do
      expect { Lint.new(model.new).public_send(test) }.not_to raise_error
    end
  end
end
