# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'tmpdir'

# In-process IPROTO server on a unix socket. Answers ID and AUTH itself.
# Other requests go to the handler block if given, otherwise to a queue the
# test drains with #next_request and answers with #reply. With
# check_schema_version it rejects requests carrying a stale schema version
# the way Tarantool does, before they reach the handler. A delay slows down
# the greeting and the ID and AUTH replies.
class FakeTarantool
  include IprotoHelpers

  attr_reader :path, :headers
  attr_accessor :schema_version

  def initialize(auth_error: nil, id_error: nil, greeting: true, check_schema_version: false, delay: 0, &handler)
    @options = { auth_error:, id_error:, greeting:, check_schema_version:, delay: }
    @headers = []
    @schema_version = 1
    @handler = handler
    @requests = Thread::Queue.new
    @write_lock = Mutex.new
    listen
  end

  def uri = "unix:#{path}"
  def auth_requests = headers.count { |header| header[0x00] == 0x07 }

  def next_request(timeout: 1)
    @requests.pop(timeout:) || raise('no request received')
  end

  def reply(request, data = [])
    write(request, 0x00, { 0x30 => data })
  end

  def reply_error(request, code:, message:)
    write(request, 0x8000 | code, { 0x31 => message })
  end

  def push(request, data)
    write(request, 0x80, { 0x30 => data })
  end

  def event(key, data = nil)
    body = { 0x57 => key }
    body[0x58] = data unless data.nil?
    @write_lock.synchronize { @socket.write(iproto_frame({ 0x00 => 0x4c, 0x01 => 0 }, body)) }
  end

  def send_raw(bytes)
    @write_lock.synchronize { @socket.write(bytes) }
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

  def listen
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'tarantool.sock')
    @server = UNIXServer.new(@path)
    @thread = Thread.new { serve }
  end

  def serve
    @socket = socket = @server.accept
    return sleep unless @options[:greeting]

    sleep @options[:delay]
    socket.write(iproto_greeting)
    loop { route(Tarantool::Client::Protocol::Codec.read_response(socket)) }
  rescue IOError, SystemCallError, Tarantool::ProtocolError
    nil
  end

  def route(request)
    @headers << request.header
    return reject_stale_schema(request) if stale_schema?(request)

    case request.type
    when 0x49 then identify(request)
    when 0x07 then authenticate(request)
    else @handler ? @handler.call(request, self) : @requests.push(request)
    end
  end

  def identify(request)
    sleep @options[:delay]
    return write(request, 0x00, { 0x54 => 3, 0x55 => [0, 1, 2, 3] }) unless @options[:id_error]

    reply_error(request, code: 48, message: @options[:id_error])
  end

  def authenticate(request)
    sleep @options[:delay]
    return write(request, 0x00, {}) unless @options[:auth_error]

    reply_error(request, code: 47, message: @options[:auth_error])
  end

  def stale_schema?(request)
    sent = request.header[0x05]
    @options[:check_schema_version] && sent && sent != schema_version
  end

  def reject_stale_schema(request)
    reply_error(request, code: 109, message: "Wrong schema version, current: #{schema_version}, " \
                                             "old: #{request.header[0x05]}")
  end

  def write(request, type, body)
    frame = iproto_frame({ 0x00 => type, 0x01 => request.sync, 0x05 => schema_version }, body)
    @write_lock.synchronize { @socket.write(frame) }
  end
end
