# frozen_string_literal: true

module Tarantool
  class Client
    module Protocol
      module Extensions
        # MP_EXT datetime: int64 epoch seconds, then optional int32 nsec, int16 tzoffset, int16 tzindex.
        # tzindex is ignored: Time keeps the offset, not the zone name.
        module Datetime
          SECONDS = 'q<'
          FULL = 'q<l<s<s<'
          LAYOUTS = { 8 => SECONDS, 16 => FULL }.freeze

          module_function

          def pack(time)
            offset, remainder = time.utc_offset.divmod(60)
            raise ArgumentError, "utc_offset #{time.utc_offset}s is not in whole minutes" unless remainder.zero?
            return [time.to_i].pack(SECONDS) if time.nsec.zero? && offset.zero?

            [time.to_i, time.nsec, offset, 0].pack(FULL)
          end

          def unpack(payload)
            layout = LAYOUTS.fetch(payload.bytesize) do
              raise ArgumentError, "malformed datetime: #{payload.bytesize} bytes"
            end
            seconds, nsec, offset = payload.unpack(layout)
            Time.at(seconds, nsec.to_i, :nsec, in: offset.to_i.zero? ? 'UTC' : offset * 60)
          end

          Extensions.register(Constants::MP_DATETIME, Time, packer: method(:pack), unpacker: method(:unpack))
        end
      end
    end
  end
end
