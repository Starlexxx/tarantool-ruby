# frozen_string_literal: true

RSpec.describe Tarantool::Crud do
  it 'has a version' do
    expect(Tarantool::Crud::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
