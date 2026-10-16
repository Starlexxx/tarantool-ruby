# frozen_string_literal: true

module Tarantool
  module Schema
    # Key part rules Tarantool enforces on tree and hash indexes, verified live on 2.11 and 3.x. Checked before
    # resolution, on what IndexSpec.build already knows, and again after, on a resolved SpaceSpec where parts
    # have inherited their type and nullability from the format.
    # @api private
    module KeyRules
      UNSUPPORTED_PART_TYPES = %w[any interval array map].freeze

      module_function

      def check(index, context)
        return unless %w[tree hash].include?(index.type)

        index.parts.each { |part| check_part_type(index, part, context) }
        check_unique(index, context)
        index.parts.each { |part| check_nullable(index, part, context) }
      end

      def check_part_type(index, part, context)
        return unless part.type && UNSUPPORTED_PART_TYPES.include?(part.type)

        raise error(index, context, "part #{part.field} of type #{part.type} can not be indexed by #{index.type}")
      end

      def check_unique(index, context)
        return unless index.type == 'hash' && !index.unique

        raise error(index, context, 'hash index must be unique')
      end

      def check_nullable(index, part, context)
        return unless index.type == 'hash' && part.is_nullable

        raise error(index, context, "hash index can not have nullable part #{part.field}")
      end

      def error(index, context, message)
        ArgumentError.new("#{"#{context}: " if context}index #{index.name}: #{message}")
      end
    end
  end
end
