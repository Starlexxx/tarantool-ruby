# frozen_string_literal: true

# Records [name, payload] once each block finishes, like an ActiveSupport subscriber reading the payload on
# finish. Events come from background threads too.
class RecordingInstrumenter
  def initialize
    @lock = Mutex.new
    @events = []
  end

  def instrument(name, payload)
    yield payload
  ensure
    @lock.synchronize { @events << [name, payload] }
  end

  def events = @lock.synchronize { @events.dup }
  def payloads(name) = events.filter_map { |event, payload| payload if event == name }
end
