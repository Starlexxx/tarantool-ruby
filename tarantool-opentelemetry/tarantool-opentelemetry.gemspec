# frozen_string_literal: true

require_relative 'lib/tarantool/opentelemetry/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-opentelemetry'
  spec.version = Tarantool::OpenTelemetry::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'OpenTelemetry spans for tarantool-client'
  spec.description = 'An instrumenter for tarantool-client that turns every request and lifecycle event into an ' \
                     'OpenTelemetry client span, with db.* attributes and without keys, tuples or credentials.'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(__dir__) { Dir['lib/**/*.rb', 'sig/**/*.rbs', 'LICENSE', 'README.md', 'CHANGELOG.md'] }
  spec.require_paths = ['lib']

  spec.add_dependency 'opentelemetry-api', '~> 1.0'
  spec.add_dependency 'tarantool-client', '~> 0.3'

  spec.metadata['source_code_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/tree/master/tarantool-opentelemetry'
  spec.metadata['changelog_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/blob/master/tarantool-opentelemetry/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Starlexxx/tarantool-ruby/issues'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
end
