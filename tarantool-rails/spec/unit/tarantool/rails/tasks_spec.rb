# frozen_string_literal: true

require 'rake'

RSpec.describe 'tarantool:schema tasks', type: :task do
  let(:client) { instance_double(Tarantool::Client) }
  let(:definition) { instance_double(Tarantool::Schema::Definition, plan: pending, apply: pending) }
  let(:pending) { ['space rails_notes', 'index rails_notes.primary'] }

  before do
    Dummy::Application.load_tasks unless Rake::Task.task_defined?('tarantool:schema:plan')
    allow(Tarantool::Rails).to receive(:admin_client).and_yield(client)
    allow(Tarantool::Rails).to receive(:schema).and_return(definition)
  end

  def run(name)
    task = Rake::Task["tarantool:schema:#{name}"]
    task.reenable

    task.execute
  end

  it 'depends on the environment' do
    prerequisites = %w[plan apply check].map { |name| Rake::Task["tarantool:schema:#{name}"].prerequisites }

    expect(prerequisites).to all(eq(['environment']))
  end

  it 'plan prints what apply would create' do
    expect { run(:plan) }.to output("space rails_notes\nindex rails_notes.primary\n").to_stdout
    expect(definition).to have_received(:plan).with(client)
  end

  it 'apply creates and prints the same lines' do
    expect { run(:apply) }.to output("space rails_notes\nindex rails_notes.primary\n").to_stdout
    expect(definition).to have_received(:apply).with(client)
  end

  it 'check exits 1 and names what is pending' do
    expect { run(:check) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      .and output("pending: space rails_notes\npending: index rails_notes.primary\n").to_stdout
  end

  context 'when the live schema equals the declaration' do
    let(:pending) { [] }

    it 'check prints nothing and passes' do
      expect { run(:check) }.not_to output.to_stdout
    end
  end

  it 'lets a mismatch propagate' do
    mismatch = Tarantool::Schema::MismatchError.new({ rails_notes: ['engine: declared memtx, actual vinyl'] })
    allow(definition).to receive(:plan).and_raise(mismatch)

    expect { run(:plan) }.to raise_error(Tarantool::Schema::MismatchError)
  end
end
