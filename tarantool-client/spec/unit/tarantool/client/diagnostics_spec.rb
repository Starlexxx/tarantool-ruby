# frozen_string_literal: true

RSpec.describe Tarantool::Client::Diagnostics do
  it 'writes the warning to the logger' do
    output = StringIO.new
    described_class.warn(Logger.new(output), 'boom')

    expect(output.string).to include('WARN -- : boom')
  end

  it 'falls back to stderr without a logger' do
    expect { described_class.warn(nil, 'boom') }.to output("boom\n").to_stderr
  end

  it 'falls back to stderr when the logger raises' do
    logger = instance_double(Logger)
    allow(logger).to receive(:warn).and_raise(IOError, 'closed stream')

    expect { described_class.warn(logger, 'boom') }.to output("boom\n").to_stderr
  end
end
