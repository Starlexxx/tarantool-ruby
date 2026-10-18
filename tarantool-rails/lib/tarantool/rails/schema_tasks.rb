# frozen_string_literal: true

module Tarantool
  module Rails
    # Helpers behind the tarantool:schema rake tasks.
    # @api private
    module SchemaTasks
      # Task arguments are one String: rails "tarantool:schema:apply[add_field]", "tarantool:schema:dump[users,codes]".
      NAME_SEPARATOR = /[\s,]+/

      module_function

      def names(argument) = argument.to_s.split(NAME_SEPARATOR).reject(&:empty?)

      def dump(path, only)
        abort "#{path} exists; set FORCE=1 to overwrite" if File.exist?(path) && ENV['FORCE'].to_s.empty?

        definition = Tarantool::Rails.admin_client do |client|
          Tarantool::Schema::Definition.from_live(client, only: only.empty? ? nil : only)
        end
        File.write(path, "# frozen_string_literal: true\n\nTarantool::Rails.schema = #{definition.to_ruby}")
        puts path
      end
    end
  end
end
