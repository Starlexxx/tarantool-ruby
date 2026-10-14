# frozen_string_literal: true

require_relative 'lib/tarantool/client/version'

Gem::Specification.new do |spec|
  spec.name = 'tarantool-client'
  spec.version = Tarantool::Client::VERSION
  spec.authors = ['Starlexxx']
  spec.email = ['apavlovskiy088@gmail.com']
  spec.summary = 'IPROTO client for Tarantool 2.11+ and 3.x'
  spec.homepage = 'https://github.com/Starlexxx/tarantool-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*.rb', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_dependency 'msgpack', '~> 1.7'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
