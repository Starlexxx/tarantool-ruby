# frozen_string_literal: true

module Tarantool
  class Client
    # Clients for the instances of one replica set. Each request goes to an instance picked by mode
    # from the role it reports through box.status, round-robin among the matches. Starts with the
    # addresses that answer; the others keep being retried in the background.
    class Pool
      MODES = %i[rw ro prefer_ro prefer_rw any].freeze

      def initialize(addresses, **options)
        raise ArgumentError, 'a pool needs at least one address' if addresses.empty?

        @members = addresses.map { |address| Member.new(address, options) }
        @lock = Mutex.new
        @turn = 0
        start_members
      rescue StandardError
        close
        raise
      end

      # Each instance resolves names against its own schema, so requests are delegated, not built here.
      Operations.public_instance_methods.each do |name|
        define_method(name) do |*args, mode: :any, **options, &block|
          client_for(mode).public_send(name, *args, **options, &block)
        end
      end

      def transaction(**, &)
        client_for(:rw).transaction(**, &)
      end

      def close
        @members&.each(&:close)
        nil
      end

      def inspect
        "#<#{self.class.name} #{@members.map(&:address).join(', ')}>"
      end

      private

      def start_members
        errors = @members.map { |member| Thread.new { member.start } }.map(&:value)
        raise NoAvailableInstanceError, "no instance reachable: #{errors.map(&:message).join('; ')}" if errors.all?
      end

      def client_for(mode)
        members = candidates(mode)
        raise NoAvailableInstanceError, "no instance available for mode #{mode.inspect}" if members.empty?

        members[@lock.synchronize { @turn += 1 } % members.size].client
      end

      def candidates(mode)
        writable, read_only = split_by_role
        case mode
        when :rw then writable
        when :ro then read_only
        when :prefer_ro then fallback(read_only, writable)
        when :prefer_rw then fallback(writable, read_only)
        when :any then writable + read_only
        else raise ArgumentError, "unknown mode #{mode.inspect}, expected one of #{MODES.join(', ')}"
        end
      end

      def fallback(preferred, other) = preferred.empty? ? other : preferred

      # Members with a known role: [writable, read-only].
      def split_by_role
        known = @members.filter_map do |member|
          read_only = member.read_only
          [member, read_only] unless read_only.nil?
        end
        known.partition { |_member, read_only| !read_only }.map { |pairs| pairs.map(&:first) }
      end
    end
  end
end
