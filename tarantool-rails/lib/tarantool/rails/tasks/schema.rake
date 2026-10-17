# frozen_string_literal: true

namespace :tarantool do
  namespace :schema do
    # rails "tarantool:schema:apply[add_field]"; several names separated by spaces or commas.
    def alter_from(args) = args[:alter].to_s.split(/[\s,]+/).reject(&:empty?).map(&:to_sym)

    desc 'Print what tarantool:schema:apply would create; fail on drift'
    task :plan, [:alter] => :environment do |_task, args|
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.plan(client, alter: alter_from(args)) }
    end

    desc 'Create missing Tarantool spaces and indexes; fail on drift'
    task :apply, [:alter] => :environment do |_task, args|
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.apply(client, alter: alter_from(args)) }
    end

    desc 'Fail unless the live schema equals the declaration, for CI'
    task :check, [:alter] => :environment do |_task, args|
      pending = Tarantool::Rails.admin_client { |client| Tarantool::Rails.schema.plan(client, alter: alter_from(args)) }
      next if pending.empty?

      pending.each { |line| puts "pending: #{line}" }
      exit 1
    end

    desc 'Write the live schema to config/tarantool_schema.rb (FORCE=1 to overwrite; spaces as [users,codes])'
    task :dump, [:only] => :environment do |_task, args|
      path = Tarantool::Rails.schema_path.to_s
      abort "#{path} exists; set FORCE=1 to overwrite" if File.exist?(path) && ENV['FORCE'].to_s.empty?

      only = args[:only].to_s.split(/[\s,]+/).reject(&:empty?)
      definition = Tarantool::Rails.admin_client do |client|
        Tarantool::Schema::Definition.from_live(client, only: only.empty? ? nil : only)
      end
      File.write(path, "# frozen_string_literal: true\n\nTarantool::Rails.schema = #{definition.to_ruby}")
      puts path
    end
  end
end
