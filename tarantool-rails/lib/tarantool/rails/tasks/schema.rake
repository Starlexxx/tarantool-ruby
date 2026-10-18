# frozen_string_literal: true

namespace :tarantool do
  namespace :schema do
    desc 'Print what tarantool:schema:apply would create; fail on drift'
    task :plan, [:alter] => :environment do |_task, args|
      alter = Tarantool::Rails::SchemaTasks.names(args[:alter]).map(&:to_sym)
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.plan(client, alter:) }
    end

    desc 'Create missing Tarantool spaces and indexes; fail on drift'
    task :apply, [:alter] => :environment do |_task, args|
      alter = Tarantool::Rails::SchemaTasks.names(args[:alter]).map(&:to_sym)
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.apply(client, alter:) }
    end

    desc 'Fail unless the live schema equals the declaration, for CI'
    task :check, [:alter] => :environment do |_task, args|
      alter = Tarantool::Rails::SchemaTasks.names(args[:alter]).map(&:to_sym)
      pending = Tarantool::Rails.admin_client { |client| Tarantool::Rails.schema.plan(client, alter:) }
      next if pending.empty?

      pending.each { |line| puts "pending: #{line}" }
      exit 1
    end

    desc 'Write the live schema to config/tarantool_schema.rb (FORCE=1 to overwrite; spaces as [users,codes])'
    task :dump, [:only] => :environment do |_task, args|
      Tarantool::Rails::SchemaTasks.dump(Tarantool::Rails.schema_path.to_s,
                                         Tarantool::Rails::SchemaTasks.names(args[:only]))
    end
  end
end
