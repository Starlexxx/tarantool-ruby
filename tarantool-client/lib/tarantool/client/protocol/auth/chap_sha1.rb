# frozen_string_literal: true

require 'digest/sha1'

module Tarantool
  class Client
    module Protocol
      # @api private
      module Auth
        # chap-sha1: proves the password to the server without sending it.
        # @api private
        module ChapSha1
          MECHANISM = 'chap-sha1'

          module_function

          def scramble(password, salt)
            hash1 = Digest::SHA1.digest(password)
            hash2 = Digest::SHA1.digest(hash1)
            hash3 = Digest::SHA1.digest(salt.byteslice(0, Constants::SCRAMBLE_SIZE) + hash2)

            hash1.bytes.zip(hash3.bytes).map { |left, right| left ^ right }.pack('C*')
          end
        end
      end
    end
  end
end
