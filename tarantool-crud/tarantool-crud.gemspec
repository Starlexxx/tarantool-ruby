# frozen_string_literal: true

require_relative 'lib/tarantool/crud/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-crud'
  spec.version = Tarantool::Crud::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'Ruby wrapper over tarantool/crud for sharded Tarantool clusters'
  spec.description = 'Per-space CRUD, conditions, pagination and batch operations over the tarantool/crud ' \
                     'module for vshard clusters on Tarantool 2.11+ and 3.x, built on tarantool-client.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md'] }
  spec.require_paths = ['lib']

  spec.add_dependency 'tarantool-client', '~> 0.2.0'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-crud'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-crud/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
