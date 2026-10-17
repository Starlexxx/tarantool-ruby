# frozen_string_literal: true

require 'generators/tarantool/model/model_generator'

RSpec.describe Tarantool::Generators::ModelGenerator do
  include_context 'with a generator root'

  let(:schema) { "Tarantool::Rails.schema = Tarantool::Schema::Definition.new do\nend\n" }
  let(:schema_with_users) do
    <<~RUBY
      Tarantool::Rails.schema = Tarantool::Schema::Definition.new do

        ensure_space :users,
                     format: [
                       { name: :id, type: :unsigned },
                       { name: :email, type: :string },
                       { name: :age, type: :unsigned, is_nullable: true }
                     ],
                     indexes: [
                       { name: :primary, parts: [:id], sequence: true }
                     ]
      end
    RUBY
  end

  before do
    FileUtils.mkdir_p(File.join(root, 'config'))
    File.write(File.join(root, 'config/tarantool_schema.rb'), schema)
  end

  it 'writes the model with id first and the typed attributes' do
    generate(described_class, 'User', 'email:string', 'age:unsigned?', 'token:uuid')

    expect(read('app/models/user.rb')).to eq(<<~RUBY)
      class User
        include Tarantool::Model

        attribute :id, :integer
        attribute :email, :string
        attribute :age, :integer
        attribute :token, Tarantool::Model::Types::UUID.new
      end
    RUBY
  end

  it 'adds the space to the schema with a sequence on id and nullable fields marked' do
    generate(described_class, 'User', 'email:string', 'age:unsigned?')

    expect(read('config/tarantool_schema.rb')).to eq(schema_with_users)
  end

  it 'keeps a caller-given id without a sequence' do
    generate(described_class, 'Code', 'id:string', 'uses:integer')

    expect(read('app/models/code.rb')).to include("attribute :id, :string\n  attribute :uses, :integer\n")
    expect(read('config/tarantool_schema.rb')).to include('{ name: :id, type: :string }',
                                                          '{ name: :primary, parts: [:id] }')
  end

  it 'namespaces the class and prefixes the space' do
    generate(described_class, 'Admin::User', 'email:string')

    expect(read('app/models/admin/user.rb')).to start_with("class Admin::User\n  include Tarantool::Model\n")
    expect(read('config/tarantool_schema.rb')).to include('ensure_space :admin_users,')
  end

  it 'leaves the schema alone with --skip-schema' do
    generate(described_class, 'User', 'email:string', '--skip-schema')

    expect(read('config/tarantool_schema.rb')).to eq(schema)
  end

  it 'writes the model alone when there is no schema file' do
    File.delete(File.join(root, 'config/tarantool_schema.rb'))
    generate(described_class, 'User', 'email:string')

    expect(File).to exist(File.join(root, 'app/models/user.rb'))
  end

  it 'rejects an unknown type naming the allowed ones and writes nothing' do
    expect { generate(described_class, 'User', 'age:float') }
      .to output('unknown type float for age; use one of integer, unsigned, string, boolean, decimal, datetime, ' \
                 "uuid, interval, binary\n").to_stderr
    expect(File).not_to exist(File.join(root, 'app/models/user.rb'))
  end

  it 'rejects a field without a type' do
    expect { generate(described_class, 'User', 'age') }.to output("age: expected name:type\n").to_stderr
  end
end
