# frozen_string_literal: true

RSpec.describe Tarantool::Crud::ManyError do
  it 'carries the result and its errors' do
    result = Tarantool::Crud::ManyResult.from_crud(
      nil, [crud_error('CallError', 'dup'), crud_error('CallError', 'skip')]
    )

    expect(described_class.new(result)).to have_attributes(
      result:, errors: result.errors, message: '2 crud operation(s) failed, first: dup'
    )
  end
end
