# frozen_string_literal: true

RSpec.describe Tarantool::Model::Storage::Crud, :crud do
  subject(:storage) { described_class.new(Tarantool::Crud::Client.new(client)) }

  let(:client) { Tarantool::Client.new(ENV.fetch('TARANTOOL_MODEL_CRUD_URI')) }

  before { Tarantool::Crud::Client.new(client).space(:users).truncate }
  after { client.close }

  it_behaves_like 'a model storage'
end
