# frozen_string_literal: true

require 'rails/generators'

# Runs a generator into a temporary root with its chatter silenced.
RSpec.shared_context 'with a generator root' do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.rm_rf(root) }

  def generate(generator, *args)
    original = $stdout
    $stdout = StringIO.new
    generator.start(args, destination_root: root)
  ensure
    $stdout = original
  end

  def read(path)
    File.read(File.join(root, path))
  end
end
