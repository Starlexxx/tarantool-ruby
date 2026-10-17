# frozen_string_literal: true

require_relative 'lib/tarantool/schema/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-schema'
  spec.version = Tarantool::Schema::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'Idempotent Tarantool schema declaration for deploys'
  spec.description = 'Declare Tarantool 2.11+ and 3.x spaces, indexes and primary key sequences in Ruby; apply ' \
                     'creates what is missing and fails with a readable diff when the live schema differs.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md'] }
  spec.require_paths = ['lib']

  spec.add_dependency 'tarantool-client', '~> 0.3'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-schema'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-schema/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
