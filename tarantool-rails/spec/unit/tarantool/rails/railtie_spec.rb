# frozen_string_literal: true

RSpec.describe Tarantool::Rails::Railtie do
  let(:pool) { instance_double(Tarantool::Client::Pool, close: nil) }

  before do
    allow(Tarantool::Client::Pool).to receive(:new).and_return(pool)
    allow(pool).to receive(:is_a?).with(Tarantool::Client::Pool).and_return(true)
  end

  after { Tarantool::Rails.disconnect! }

  it 'reads the environment section of config/tarantool.yml' do
    uri = ENV.fetch('TARANTOOL_URI', 'tcp://app:secret@localhost:3301')

    expect(Tarantool::Rails.config.to_h).to include(addresses: [uri], client_options: { request_timeout: 5 })
  end

  it 'defaults the schema path to config/tarantool_schema.rb' do
    expect(Tarantool::Rails.schema_path).to eq(Dummy::Application.root.join('config/tarantool_schema.rb'))
  end

  it 'gives models the configured storage on first use' do
    expect(Tarantool::Model.default_storage).to be(Tarantool::Rails.storage)
  end

  it 'points models at the new storage after a disconnect' do
    old = Tarantool::Model.default_storage
    Tarantool::Rails.disconnect!

    expect(Tarantool::Model.default_storage).to be(Tarantool::Rails.storage)
    expect(Tarantool::Model.default_storage).not_to be(old)
  end

  it 'attaches the log subscriber' do
    expect(ActiveSupport::Notifications.notifier.listening?('request.tarantool')).to be(true)
  end

  it 'adds the controller runtime to controllers' do
    expect(ActionController::Base).to include(Tarantool::Rails::ControllerRuntime)
  end
end
