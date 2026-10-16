# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'tmpdir'

# Unix socket server that sends the greeting one byte at a time, interval seconds apart, and nothing more.
class DrippingTarantool
  include IprotoHelpers

  def initialize(interval:)
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'tarantool.sock')
    @server = UNIXServer.new(@path)
    @thread = Thread.new { drip(@server.accept, interval) }
  end

  def uri = "unix:#{@path}"

  def stop
    @server.close
    @thread.kill.join

    FileUtils.remove_entry(@dir)
  end

  private

  def drip(socket, interval)
    iproto_greeting.each_char do |byte|
      socket.write(byte)
      sleep interval
    end
  rescue IOError, SystemCallError
    nil
  ensure
    socket&.close
  end
end
