# frozen_string_literal: true

RSpec.describe Tarantool::Crud::ManyResult do
  it 'decodes rows and per-row errors' do
    result = described_class.from_crud(
      crud_result([1, 'a']), [crud_error('CallError', 'dup', operation_data: [2, 'b'])]
    )

    expect(result.to_a).to eq([{ id: 1, name: 'a' }])
    expect(result.errors).to contain_exactly(
      an_instance_of(Tarantool::Crud::CallError).and(having_attributes(operation_data: [2, 'b']))
    )
    expect(result).not_to be_success
  end

  it 'succeeds without errors' do
    expect(described_class.from_crud(crud_result([1, 'a']), nil)).to have_attributes(errors: [], success?: true)
  end

  it 'keeps the error of a call that failed as a whole' do
    result = described_class.from_crud(nil, [crud_error('InsertManyError', 'At least one tuple expected')])

    expect(result).to have_attributes(to_a: [], errors: [an_instance_of(Tarantool::Crud::InsertManyError)])
  end
end
