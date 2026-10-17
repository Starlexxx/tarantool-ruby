# frozen_string_literal: true

# Task arguments are one String: rails "tarantool:schema:apply[add_field]", "tarantool:schema:dump[users,codes]".
TARANTOOL_SCHEMA_NAME_SEPARATOR = /[\s,]+/

def tarantool_schema_names(argument) = argument.to_s.split(TARANTOOL_SCHEMA_NAME_SEPARATOR).reject(&:empty?)

def tarantool_schema_dump(path, only)
  abort "#{path} exists; set FORCE=1 to overwrite" if File.exist?(path) && ENV['FORCE'].to_s.empty?

  definition = Tarantool::Rails.admin_client do |client|
    Tarantool::Schema::Definition.from_live(client, only: only.empty? ? nil : only)
  end
  File.write(path, "# frozen_string_literal: true\n\nTarantool::Rails.schema = #{definition.to_ruby}")
  puts path
end

namespace :tarantool do
  namespace :schema do
    desc 'Print what tarantool:schema:apply would create; fail on drift'
    task :plan, [:alter] => :environment do |_task, args|
      alter = tarantool_schema_names(args[:alter]).map(&:to_sym)
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.plan(client, alter:) }
    end

    desc 'Create missing Tarantool spaces and indexes; fail on drift'
    task :apply, [:alter] => :environment do |_task, args|
      alter = tarantool_schema_names(args[:alter]).map(&:to_sym)
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.apply(client, alter:) }
    end

    desc 'Fail unless the live schema equals the declaration, for CI'
    task :check, [:alter] => :environment do |_task, args|
      alter = tarantool_schema_names(args[:alter]).map(&:to_sym)
      pending = Tarantool::Rails.admin_client { |client| Tarantool::Rails.schema.plan(client, alter:) }
      next if pending.empty?

      pending.each { |line| puts "pending: #{line}" }
      exit 1
    end

    desc 'Write the live schema to config/tarantool_schema.rb (FORCE=1 to overwrite; spaces as [users,codes])'
    task :dump, [:only] => :environment do |_task, args|
      tarantool_schema_dump(Tarantool::Rails.schema_path.to_s, tarantool_schema_names(args[:only]))
    end
  end
end
