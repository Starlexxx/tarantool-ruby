# frozen_string_literal: true

RSpec.describe Tarantool::Model::Error do
  it 'is a Tarantool::Error' do
    expect(described_class.new).to be_a(Tarantool::Error)
  end

  it 'names the model and key of a missing record' do
    error = Tarantool::Model::RecordNotFound.new(String, [1, 2])

    expect([error.model, error.key, error.message]).to eq([String, [1, 2], 'String with key [1, 2] not found'])
  end

  it 'reports the validation errors of an invalid record' do
    record = Struct.new(:errors).new(instance_double(ActiveModel::Errors, full_messages: ["Email can't be blank"]))

    expect(Tarantool::Model::RecordInvalid.new(record)).to have_attributes(record:, message: "Email can't be blank")
  end

  it 'keeps the record that was not saved' do
    record = Object.new

    expect(Tarantool::Model::RecordNotSaved.new(record)).to have_attributes(record:)
  end
end
