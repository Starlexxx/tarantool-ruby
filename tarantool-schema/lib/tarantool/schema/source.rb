# frozen_string_literal: true

module Tarantool
  module Schema
    # Ruby source of a definition, from its normalized Hash: a Definition.new block with one ensure_space per
    # space and one ensure_index per index on a space declared elsewhere. Defaults are left out and a part that
    # inherits everything from its field is a bare name, so the result reads like a hand-written declaration.
    # Grants come last, one line each.
    # @api private
    module Source
      WIDTH = 120
      ARGUMENT_INDENT = ' ' * 15
      ENTRY_INDENT = ' ' * 17

      module_function

      def render(spaces, external, grants = [])
        entries = spaces.map { |name, space| space(name, space) }
        entries += external.map { |name, indexes| indexes(name, indexes) }
        entries << grants.map { |grant| grant(grant) }.join("\n") if grants.any?

        "Tarantool::Schema::Definition.new do\n#{entries.join("\n\n")}#{"\n" if entries.any?}end\n"
      end

      def grant(grant)
        privileges = grant[:privileges]
        literal = privileges.one? ? symbol(privileges.first) : "%i[#{privileges.join(' ')}]"

        "  grant #{symbol(grant[:user])}, #{literal}, on: #{symbol(grant[:space])}"
      end

      def space(name, space)
        fields = space[:format].to_h { |field| [field[:name], field] }
        format = list('format', space[:format].map { |field| field(field) })
        indexes = list('indexes', space[:indexes].map { |index| index(index, fields) })

        "  ensure_space #{symbol(name)},\n#{engine(space)}#{format},\n#{indexes}"
      end

      def engine(space) = space[:engine] == 'memtx' ? '' : "#{ARGUMENT_INDENT}engine: #{symbol(space[:engine])},\n"

      def indexes(space, indexes)
        indexes.map { |index| "  ensure_index #{symbol(space)}, #{symbol(index[:name])}, #{options(index, {})}" }
               .join("\n")
      end

      def list(key, entries)
        "#{ARGUMENT_INDENT}#{key}: [\n#{entries.map { |entry| ENTRY_INDENT + entry }.join(",\n")}\n#{ARGUMENT_INDENT}]"
      end

      def field(field)
        nullable = field[:is_nullable] ? ', is_nullable: true' : ''

        "{ name: #{symbol(field[:name])}, type: #{symbol(field[:type])}#{nullable} }"
      end

      def index(index, fields)
        line = "{ name: #{symbol(index[:name])}, #{options(index, fields)} }"
        return line if ENTRY_INDENT.size + line.size <= WIDTH

        wrapped_index(index, fields)
      end

      def wrapped_index(index, fields)
        indent = "#{ENTRY_INDENT}  "
        parts = index[:parts].map { |part| "#{indent}  #{part(part, fields)}" }.join(",\n")
        head = "{ name: #{symbol(index[:name])},#{type_option(index).rstrip}"
        tail = [unique_option(index), sequence_option(index)].join

        "#{head}\n#{indent}parts: [\n#{parts}\n#{indent}]#{tail} }"
      end

      def options(index, fields)
        parts = index[:parts].map { |part| part(part, fields) }.join(', ')

        "#{type_option(index).lstrip}parts: [#{parts}]#{unique_option(index)}#{sequence_option(index)}"
      end

      def type_option(index) = index[:type] == 'tree' ? ' ' : " type: #{symbol(index[:type])}, "

      def unique_option(index) = index[:unique] ? '' : ', unique: false'

      def sequence_option(index) = index[:sequence] ? ', sequence: true' : ''

      # Unresolved parts (external indexes) carry nil for what they inherit; resolved ones repeat the field.
      def part(part, fields)
        options = part_options(part, fields[part[:field]])
        return symbol(part[:field]) if options.empty? && part[:path].nil?

        "{ field: #{symbol(part[:field])}, #{options.map { |key, value| "#{key}: #{value}" }.join(', ')} }"
      end

      # A path part always declares its type; everything else is written only when it differs from the field.
      def part_options(part, field)
        options = differing(part, field)
        options[:type] = part[:type] if part[:path]
        options = options.sort_by { |key, _| key == :type ? 0 : 1 }.to_h { |key, value| [key, literal(value)] }
        options[:path] = string(part[:path]) if part[:path]

        options
      end

      def differing(part, field)
        options = { type: part[:type], is_nullable: part[:is_nullable] }.compact
        return options unless field

        options.reject { |key, value| field[key] == value }
      end

      def literal(value) = value.is_a?(String) ? symbol(value) : value.to_s

      def symbol(name) = name.to_sym.inspect

      def string(value) = value.match?(/['\\]/) ? value.inspect : "'#{value}'"
    end
  end
end
