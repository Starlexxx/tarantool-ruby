# frozen_string_literal: true

require_relative 'lib/tarantool/model/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-model'
  spec.version = Tarantool::Model::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'ActiveModel-based models for Tarantool spaces'
  spec.description = 'Attributes, validations, callbacks, dirty tracking and index-based queries with keyset ' \
                     'pagination over Tarantool 2.11+ and 3.x spaces, through tarantool-client or tarantool-crud.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'sig/**/*.rbs', 'LICENSE', 'README.md', 'CHANGELOG.md'] }
  spec.require_paths = ['lib']

  spec.add_dependency 'activemodel', '>= 7.1', '< 9'
  spec.add_dependency 'tarantool-client', '~> 0.3'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-model'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-model/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
