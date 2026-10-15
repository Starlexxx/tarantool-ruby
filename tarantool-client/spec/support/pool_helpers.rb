# frozen_string_literal: true

# FakeTarantool instances standing in for replica set members.
module PoolHelpers
  # Answers eval with the server name and reports { 'is_ro' => roles[name] } through box.status. Like
  # Tarantool it sends the value once per connection; the WATCHes that follow are acks.
  def status_server(name, roles)
    announced = {}
    FakeTarantool.new do |request, fake|
      case request.type
      when 0x08 then fake.reply(request, [name])
      when 0x4a then announce(fake, announced, roles[name])
      else fake.reply(request, [])
      end
    end
  end

  def leftover_threads
    Thread.list.select { |thread| thread.alive? && thread.name&.match?(/\Atarantool-(pool|reconnect|watchers)/) }
  end

  def change_role(server, roles, name, read_only)
    roles[name] = read_only
    server.event('box.status', { 'is_ro' => read_only })
  end

  private

  def announce(fake, announced, read_only)
    return if announced[fake.connections]

    announced[fake.connections] = true
    fake.event('box.status', { 'is_ro' => read_only })
  end
end
