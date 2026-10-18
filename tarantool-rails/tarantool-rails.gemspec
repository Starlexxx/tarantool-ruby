# frozen_string_literal: true

require_relative 'lib/tarantool/rails/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-rails'
  spec.version = Tarantool::Rails::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'Rails integration for tarantool-client, tarantool-model and tarantool-schema'
  spec.description = 'config/tarantool.yml per environment, one connection pool per process, models on it ' \
                     'without an initializer, ActiveRecord-style log lines, schema rake tasks and generators.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'sig/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md'].select { |path| File.file?(path) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'railties', '>= 7.1', '< 9'
  spec.add_dependency 'tarantool-client', '~> 0.3'
  spec.add_dependency 'tarantool-model', '~> 0.3'
  spec.add_dependency 'tarantool-schema', '~> 0.3'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-rails'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-rails/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
