# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'tmpdir'

# Minimal concurrent IPROTO server for fork tests: one thread per connection.
# Handles ID and AUTH automatically. Sends a box.status event on WATCH 'box.status'
# so Pool members learn their role. Other requests go to the optional handler block.
class ForkFakeTarantool
  include IprotoHelpers

  attr_reader :path
  attr_accessor :refusing

  def initialize(read_only: false, &handler)
    @read_only = read_only
    @refusing = false
    @handler = handler
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'tarantool.sock')
    @server = UNIXServer.new(@path)
    @thread = Thread.new { serve }
  end

  def uri = "unix:#{@path}"

  # Start a new accept loop in the child after fork (parent's thread died at fork). The listening socket is
  # rebound: the fd is shared with the parent, whose accept loop would otherwise take about half of the
  # child's connections and, when refusing, drop them.
  def restart_after_fork
    File.unlink(@path)
    @server = UNIXServer.new(@path)
    @thread = Thread.new { serve }
  end

  def stop
    @server.close
    @thread.kill.join
    FileUtils.remove_entry(@dir)
  end

  private

  def serve
    loop do
      socket = @server.accept
      if @refusing
        socket.close
      else
        Thread.new(socket) { |s| serve_connection(s) }
      end
    end
  rescue IOError, SystemCallError
    nil
  end

  def serve_connection(socket)
    socket.write(iproto_greeting)
    loop { route(socket, Tarantool::Client::Protocol::Codec.read_response(socket)) }
  rescue IOError, SystemCallError, Tarantool::ProtocolError
    nil
  ensure
    socket.close
  end

  def route(socket, request)
    case request.type
    when 0x49 then write(socket, request, 0x00, { 0x54 => 3, 0x55 => [0, 1, 2, 3] })
    when 0x07 then write(socket, request, 0x00, {})
    when 0x4a then handle_watch(socket, request)
    when 0x4b then nil
    else write(socket, request, 0x00, { 0x30 => (@handler ? @handler.call(request) : []) })
    end
  end

  def handle_watch(socket, request)
    return unless request.body[0x57] == 'box.status'

    event_body = { 0x57 => 'box.status', 0x58 => { 'is_ro' => @read_only } }
    socket.write(iproto_frame({ 0x00 => 0x4c, 0x01 => 0 }, event_body))
  end

  def write(socket, request, type, body)
    frame = iproto_frame({ 0x00 => type, 0x01 => request.sync, 0x05 => 1 }, body)
    socket.write(frame)
  end
end
