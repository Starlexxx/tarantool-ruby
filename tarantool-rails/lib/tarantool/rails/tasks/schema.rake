# frozen_string_literal: true

namespace :tarantool do
  namespace :schema do
    desc 'Print what tarantool:schema:apply would create; fail on drift'
    task plan: :environment do
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.plan(client) }
    end

    desc 'Create missing Tarantool spaces and indexes; fail on drift'
    task apply: :environment do
      Tarantool::Rails.admin_client { |client| puts Tarantool::Rails.schema.apply(client) }
    end

    desc 'Fail unless the live schema equals the declaration, for CI'
    task check: :environment do
      pending = Tarantool::Rails.admin_client { |client| Tarantool::Rails.schema.plan(client) }
      next if pending.empty?

      pending.each { |line| puts "pending: #{line}" }
      exit 1
    end
  end
end
