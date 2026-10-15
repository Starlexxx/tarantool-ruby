# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_EXT decimal: msgpack int scale, then BCD digits with a trailing sign nibble.
        module Decimal
          MAX_DIGITS = 38
          NEGATIVE_SIGNS = %w[b d].freeze

          module_function

          def pack(value)
            raise ArgumentError, "cannot encode #{value} as decimal" unless value.finite?

            scale, nibbles = scale_and_nibbles(value)
            MessagePack.pack(scale) + [nibbles].pack('H*')
          end

          def unpack(payload)
            unpacker = MessagePack::Unpacker.new.feed(payload)
            scale = unpacker.read
            nibbles = unpacker.buffer.read_all.unpack1('H*')
            unless scale.is_a?(Integer) && nibbles.match?(/\A\d+[a-f]\z/)
              raise ArgumentError, "malformed decimal: #{nibbles}"
            end

            sign = NEGATIVE_SIGNS.include?(nibbles[-1]) ? '-' : ''
            BigDecimal("#{sign}#{nibbles[0...-1]}e#{-scale}")
          end

          def scale_and_nibbles(value)
            sign, digits, _base, exponent = value.split
            if digits.length > MAX_DIGITS
              raise ArgumentError, "decimal exceeds #{MAX_DIGITS} digits: #{value.to_s('F')}"
            end

            scale = value.zero? ? 0 : digits.length - exponent
            scale, digits = expand_negative_scale(scale, digits)
            nibbles = digits + (sign.negative? ? 'd' : 'c')
            [scale, nibbles.length.odd? ? "0#{nibbles}" : nibbles]
          end
          private_class_method :scale_and_nibbles

          # Tarantool itself writes whole numbers with scale 0 and trailing zero digits;
          # keeping a negative scale when that would overflow MAX_DIGITS stays lossless.
          def expand_negative_scale(scale, digits)
            return [scale, digits] if scale >= 0 || digits.length - scale > MAX_DIGITS

            [0, digits + ('0' * -scale)]
          end
          private_class_method :expand_negative_scale

          Extensions.register(Constants::MP_DECIMAL, BigDecimal, packer: method(:pack), unpacker: method(:unpack))
        end
      end
    end
  end
end
