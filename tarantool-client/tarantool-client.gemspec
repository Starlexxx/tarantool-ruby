# frozen_string_literal: true

require_relative 'lib/tarantool/client/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-client'
  spec.version = Tarantool::Client::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'IPROTO client for Tarantool 2.11+ and 3.x'
  spec.description = 'Thread-safe IPROTO client for Tarantool 2.11+ and 3.x: CRUD by space and index name, SQL, ' \
                     'interactive transactions, push, watchers, background reconnect and a role-aware pool.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md'] }
  spec.require_paths = ['lib']

  spec.add_dependency 'bigdecimal', '>= 3.1', '< 5'
  spec.add_dependency 'msgpack', '~> 1.7'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-client'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-client/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
