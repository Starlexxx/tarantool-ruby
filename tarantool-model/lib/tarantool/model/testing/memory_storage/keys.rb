# frozen_string_literal: true

module Tarantool
  module Model
    module Testing
      class MemoryStorage
        # Shape checks shared by the declaration classes; a bad declaration raises ArgumentError naming its owner.
        # @api private
        module Keys
          module_function

          def check!(declaration, allowed, owner)
            raise ArgumentError, "#{owner} must be a Hash, got #{declaration.inspect}" unless declaration.is_a?(Hash)

            unknown = declaration.keys - allowed
            raise ArgumentError, "#{owner} has unknown keys #{unknown.join(', ')}" if unknown.any?
          end

          def fetch!(declaration, key, owner)
            declaration.fetch(key) { raise ArgumentError, "#{owner} has no #{key}" }
          end

          def one_of!(value, allowed, owner)
            name = value.to_s
            raise ArgumentError, "#{owner} has unknown type #{value.inspect}" unless allowed.include?(name)

            name
          end

          def distinct!(names, owner)
            duplicates = names.tally.select { |_name, count| count > 1 }.keys
            raise ArgumentError, "#{owner} has duplicate names #{duplicates.join(', ')}" if duplicates.any?
          end
        end
      end
    end
  end
end
