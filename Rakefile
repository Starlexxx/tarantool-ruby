# frozen_string_literal: true

# Checks the RBS signatures of every gem: `rbs validate` over all sig directories together, then each gem's
# unit specs under rbs/test with its public classes as targets.
GEMS = %w[tarantool-client tarantool-crud tarantool-schema tarantool-model tarantool-opentelemetry
          tarantool-rails].freeze
STDLIB = %w[bigdecimal logger].freeze
TARGETS = {
  'tarantool-client' => %w[Tarantool::Client Tarantool::Client::Pool Tarantool::Client::Stream
                           Tarantool::Client::Watcher Tarantool::Client::SqlResult Tarantool::Client::PreparedStatement
                           Tarantool::Client::SpaceInfo Tarantool::Client::IndexInfo Tarantool::Client::Row
                           Tarantool::Client::Page Tarantool::Client::Configuration Tarantool::Client::UUID
                           Tarantool::Client::Interval Tarantool::Client::BoxError Tarantool::ServerError
                           Tarantool::AuthenticationError],
  'tarantool-crud' => %w[Tarantool::Crud::Client Tarantool::Crud::Space Tarantool::Crud::Result
                         Tarantool::Crud::ManyResult Tarantool::Crud::Error Tarantool::Crud::ManyError],
  'tarantool-schema' => %w[Tarantool::Schema::Definition Tarantool::Schema::MismatchError],
  'tarantool-model' => %w[Tarantool::Model Tarantool::Model::Relation Tarantool::Model::Storage::Box
                          Tarantool::Model::Storage::Crud Tarantool::Model::Testing::MemoryStorage
                          Tarantool::Model::Types::UUID Tarantool::Model::Types::Interval Tarantool::Model::Types::Binary
                          Tarantool::Model::RecordNotFound Tarantool::Model::RecordInvalid Tarantool::Model::RecordNotSaved
                          Tarantool::Model::StaleObjectError],
  'tarantool-opentelemetry' => %w[Tarantool::OpenTelemetry::Instrumenter],
  'tarantool-rails' => %w[Tarantool::Rails Tarantool::Rails::Configuration Tarantool::Rails::LogSubscriber]
}.freeze

def sig_options
  (STDLIB.map { |lib| "-r #{lib}" } + GEMS.map { |gem| "-I #{File.expand_path("#{gem}/sig", __dir__)}" }).join(' ')
end

desc 'Validate the RBS signatures and run every unit suite under rbs/test'
task :rbs do
  sh "bundle exec rbs #{sig_options} validate"
  GEMS.each do |gem|
    env = {
      'RUBYOPT' => '-rrbs/test/setup', 'RBS_TEST_OPT' => sig_options, 'RBS_TEST_TARGET' => TARGETS.fetch(gem).join(','),
      'RBS_TEST_RAISE' => 'true', 'RBS_TEST_LOGLEVEL' => 'error'
    }
    sh(env, 'bundle exec rspec', chdir: gem)
  end
end
