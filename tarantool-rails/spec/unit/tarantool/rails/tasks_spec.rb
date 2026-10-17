# frozen_string_literal: true

require 'rake'
require 'tmpdir'

RSpec.describe 'tarantool:schema tasks', type: :task do
  let(:client) { instance_double(Tarantool::Client) }
  let(:definition) { instance_double(Tarantool::Schema::Definition, plan: pending, apply: pending) }
  let(:pending) { ['space rails_notes', 'index rails_notes.primary'] }

  before do
    Dummy::Application.load_tasks unless Rake::Task.task_defined?('tarantool:schema:plan')
    allow(Tarantool::Rails).to receive(:admin_client).and_yield(client)
    allow(Tarantool::Rails).to receive(:schema).and_return(definition)
  end

  def run(name, *arguments)
    task = Rake::Task["tarantool:schema:#{name}"]
    task.reenable

    task.execute(Rake::TaskArguments.new(task.arg_names, arguments))
  end

  it 'depends on the environment' do
    prerequisites = %w[plan apply check dump].map { |name| Rake::Task["tarantool:schema:#{name}"].prerequisites }

    expect(prerequisites).to all(eq(['environment']))
  end

  it 'plan prints what apply would create' do
    expect { run(:plan) }.to output("space rails_notes\nindex rails_notes.primary\n").to_stdout
    expect(definition).to have_received(:plan).with(client, alter: [])
  end

  it 'apply creates and prints the same lines' do
    expect { run(:apply) }.to output("space rails_notes\nindex rails_notes.primary\n").to_stdout
    expect(definition).to have_received(:apply).with(client, alter: [])
  end

  it 'passes the alter argument through' do
    run(:apply, 'add_field')
    run(:plan, 'add_field, other')

    expect(definition).to have_received(:apply).with(client, alter: [:add_field])
    expect(definition).to have_received(:plan).with(client, alter: %i[add_field other])
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

  describe 'dump' do
    let(:live) { instance_double(Tarantool::Schema::Definition, to_ruby: "Tarantool::Schema::Definition.new do\nend\n") }
    let(:path) { File.join(Dir.mktmpdir, 'tarantool_schema.rb') }

    before do
      Tarantool::Rails.schema_path = path
      allow(Tarantool::Schema::Definition).to receive(:from_live).and_return(live)
    end

    after { Tarantool::Rails.schema_path = Dummy::Application.root.join('config/tarantool_schema.rb') }

    it 'writes the live schema as an assignment to Tarantool::Rails.schema' do
      expect { run(:dump) }.to output("#{path}\n").to_stdout
      expect(File.read(path)).to eq("# frozen_string_literal: true\n\nTarantool::Rails.schema = " \
                                    "Tarantool::Schema::Definition.new do\nend\n")
      expect(Tarantool::Schema::Definition).to have_received(:from_live).with(client, only: nil)
    end

    it 'restricts the spaces with the only argument' do
      run(:dump, 'users, codes')

      expect(Tarantool::Schema::Definition).to have_received(:from_live).with(client, only: %w[users codes])
    end

    it 'refuses to overwrite an existing file without FORCE' do
      File.write(path, 'keep')

      expect { run(:dump) }.to raise_error(SystemExit).and output(/exists; set FORCE=1/).to_stderr
      expect(File.read(path)).to eq('keep')
    end

    it 'overwrites with FORCE' do
      File.write(path, 'old')
      stub_const('ENV', ENV.to_h.merge('FORCE' => '1'))

      run(:dump)

      expect(File.read(path)).to start_with('# frozen_string_literal: true')
    end
  end
end
