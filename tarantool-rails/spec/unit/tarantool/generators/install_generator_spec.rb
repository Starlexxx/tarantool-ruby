# frozen_string_literal: true

require 'generators/tarantool/install/install_generator'

RSpec.describe Tarantool::Generators::InstallGenerator do
  include_context 'with a generator root'

  before { generate(described_class) }

  it 'writes config/tarantool.yml with every environment' do
    expect(read('config/tarantool.yml')).to include('default: &default', 'development:', 'test:', 'production:',
                                                    'admin_uri: <%= ENV["TARANTOOL_ADMIN_URI"] %>')
  end

  it 'writes an empty schema that assigns Tarantool::Rails.schema' do
    expect(read('config/tarantool_schema.rb'))
      .to include('Tarantool::Rails.schema = Tarantool::Schema::Definition.new do')
  end
end
