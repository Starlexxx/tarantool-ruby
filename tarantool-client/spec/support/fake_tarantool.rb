# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'tmpdir'

# In-process IPROTO server on a unix socket. Answers ID and AUTH itself.
# Other requests go to the handler block if given, otherwise to a queue the
# test drains with #next_request and answers with #reply.
class FakeTarantool
  include IprotoHelpers

  attr_reader :path

  def initialize(auth_error: nil, &handler)
    @auth_error = auth_error
    @handler = handler
    @requests = Thread::Queue.new
    @write_lock = Mutex.new
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'tarantool.sock')
    @server = UNIXServer.new(@path)
    @thread = Thread.new { serve }
  end

  def uri = "unix:#{path}"

  def next_request(timeout: 1)
    @requests.pop(timeout:) || raise('no request received')
  end

  def reply(request, data = [])
    write(request, 0x00, { 0x30 => data })
  end

  def reply_error(request, code:, message:)
    write(request, 0x8000 | code, { 0x31 => message })
  end

  def disconnect
    @socket&.close
  end

  def stop
    disconnect
    @server.close
    @thread.kill.join
    FileUtils.remove_entry(@dir)
  end

  private

  def serve
    @socket = socket = @server.accept
    socket.write(iproto_greeting)
    loop { route(Tarantool::Client::Protocol::Codec.read_response(socket)) }
  rescue IOError, SystemCallError
    nil
  end

  def route(request)
    case request.type
    when 0x49 then write(request, 0x00, { 0x54 => 3, 0x55 => [0, 1, 2, 3] })
    when 0x07 then authenticate(request)
    else @handler ? @handler.call(request, self) : @requests.push(request)
    end
  end

  def authenticate(request)
    return write(request, 0x00, {}) unless @auth_error

    reply_error(request, code: 47, message: @auth_error)
  end

  def write(request, type, body)
    frame = iproto_frame({ 0x00 => type, 0x01 => request.sync, 0x05 => 1 }, body)
    @write_lock.synchronize { @socket.write(frame) }
  end
end
