# frozen_string_literal: true

RSpec.describe Tarantool::Model do
  it 'has a version' do
    expect(Tarantool::Model::VERSION).to eq('0.1.0')
  end
end
