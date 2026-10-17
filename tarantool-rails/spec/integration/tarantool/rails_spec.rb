# frozen_string_literal: true

require 'rake'

RSpec.describe Tarantool::Rails, :integration do
  before do
    Dummy::Application.load_tasks unless Rake::Task.task_defined?('tarantool:schema:apply')
    described_class.disconnect!
    drop_notes
    stub_const('Note', Class.new do
      include Tarantool::Model

      self.space_name = :rails_notes
      attribute :id, :integer
      attribute :body, :string
    end)
  end

  after do
    drop_notes
    described_class.disconnect!
  end

  def drop_notes
    described_class.admin_client do |client|
      client.eval(<<~LUA)
        if box.space.rails_notes then box.space.rails_notes:drop() end
        if box.sequence.rails_notes_seq then box.sequence.rails_notes_seq:drop() end
      LUA
    end
  end

  def run(name)
    task = Rake::Task["tarantool:schema:#{name}"]
    task.reenable

    task.execute
  end

  it 'applies the schema, then check and plan have nothing to report' do
    expect { run(:apply) }.to output("space rails_notes\nindex rails_notes.primary\n").to_stdout
    expect { run(:check) }.not_to output.to_stdout
    expect { run(:plan) }.not_to output.to_stdout
  end

  it 'saves and reads a model through the configured storage and logs the request' do
    run(:apply)
    Dummy::LOG.truncate(0)
    Dummy::LOG.rewind

    note = Note.create!(body: 'hello')

    expect(Note.find(note.id).body).to eq('hello')
    expect(Dummy::LOG.string).to include('Tarantool insert rails_notes', 'Tarantool select rails_notes')
  end
end
