# frozen_string_literal: true

require 'action_controller'

RSpec.describe Tarantool::Rails::ControllerRuntime do
  let(:controller) do
    Class.new(ActionController::Base) do
      include Tarantool::Rails::ControllerRuntime

      def index
        Tarantool::Rails::LogSubscriber.runtime = 1.5

        render plain: 'ok'
      end
    end
  end
  let(:payloads) { [] }

  before do
    stub_const('NotesController', controller)
    Tarantool::Rails::LogSubscriber.runtime = 7.0
  end

  def dispatch
    subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |event|
      payloads << event.payload
    end
    NotesController.action(:index).call(Rack::MockRequest.env_for('/notes'))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'reports the time spent during the action, not before it' do
    dispatch

    expect(payloads.sole[:tarantool_runtime]).to eq(1.5)
  end

  it 'adds the share to the Completed line' do
    expect(NotesController.log_process_action({ view_runtime: 2.0, tarantool_runtime: 1.5 }))
      .to eq(['Views: 2.0ms', 'Tarantool: 1.5ms'])
  end

  it 'leaves the Completed line alone without a runtime' do
    expect(NotesController.log_process_action({ view_runtime: 2.0 })).to eq(['Views: 2.0ms'])
  end
end
