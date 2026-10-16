# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_EXT interval: uint8 count, then (uint8 field id, msgpack int) pairs for non-zero values.
        # @api private
        module Interval
          FIELD_NAMES = %i[year month week day hour min sec nsec adjust].freeze
          FIELDS = FIELD_NAMES.each_with_index.to_h { |name, id| [id, name] }.freeze
          ADJUSTS = { excess: 0, none: 1, last: 2 }.freeze

          module_function

          def pack(interval)
            pairs = codes(interval).each_with_index.reject { |code, _id| code.zero? }

            pairs.reduce([pairs.size].pack('C')) do |payload, (code, id)|
              payload + [id].pack('C') + MessagePack.pack(code)
            end
          end

          # Count and field ids are uint8 below 0x80, which are byte-identical to positive fixints,
          # so the whole payload reads as a msgpack stream.
          def unpack(payload)
            count, *pairs = MessagePack::Unpacker.new.feed(payload).each.to_a
            raise ArgumentError, 'malformed interval: field count mismatch' unless pairs.size == count * 2

            attributes = pairs.each_slice(2).to_h { |id, value| [FIELDS.fetch(id), value] }
            attributes[:adjust] = decode_adjust(attributes.fetch(:adjust, 0))

            Client::Interval.new(**attributes)
          end

          def codes(interval)
            values = interval.to_h.merge(adjust: encode_adjust(interval.adjust))

            FIELD_NAMES.map { |name| values.fetch(name) }
          end

          def encode_adjust(adjust)
            ADJUSTS.fetch(adjust) { raise ArgumentError, "unknown interval adjust: #{adjust.inspect}" }
          end

          def decode_adjust(code)
            ADJUSTS.key(code) || raise(ArgumentError, "malformed interval: adjust #{code}")
          end

          private_class_method :codes, :encode_adjust, :decode_adjust

          Extensions.register(
            Constants::MP_INTERVAL, Client::Interval, packer: method(:pack), unpacker: method(:unpack)
          )
        end
      end
    end
  end
end
