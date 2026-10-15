# frozen_string_literal: true

RSpec.describe Tarantool::Crud::Error do
  {
    'InsertError' => Tarantool::Crud::InsertError,
    'ReplaceError' => Tarantool::Crud::ReplaceError,
    'UpsertError' => Tarantool::Crud::UpsertError,
    'GetError' => Tarantool::Crud::GetError,
    'UpdateError' => Tarantool::Crud::UpdateError,
    'DeleteError' => Tarantool::Crud::DeleteError,
    'SelectError' => Tarantool::Crud::SelectError,
    'CountError' => Tarantool::Crud::CountError,
    'BorderError' => Tarantool::Crud::MinMaxError,
    'LenError' => Tarantool::Crud::LenError,
    'TruncateError' => Tarantool::Crud::TruncateError,
    'CallError' => Tarantool::Crud::CallError,
    'InsertManyError' => Tarantool::Crud::InsertManyError,
    'ReplaceManyError' => Tarantool::Crud::ReplaceManyError,
    'UpsertManyError' => Tarantool::Crud::UpsertManyError
  }.each do |class_name, error_class|
    it "maps #{class_name} to #{error_class}" do
      expect(described_class.from(crud_error(class_name))).to be_an_instance_of(error_class)
    end
  end

  it 'maps unknown class names to the base error' do
    expect(described_class.from(crud_error('ShardingError'))).to be_an_instance_of(described_class)
  end

  it 'keeps the fields of the crud error' do
    error = described_class.from(crud_error('CallError', 'Duplicate key', operation_data: [1, 'a']))

    expect(error).to have_attributes(
      message: 'Duplicate key', class_name: 'CallError', str: 'CallError: Duplicate key',
      file: 'crud/insert.lua', line: 10, operation_data: [1, 'a']
    )
  end

  it 'belongs to the Tarantool error hierarchy' do
    expect(described_class.new('boom')).to be_a(Tarantool::Error)
  end
end
