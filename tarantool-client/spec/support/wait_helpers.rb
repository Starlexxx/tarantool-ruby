# frozen_string_literal: true

# Polling for state that another thread changes.
module WaitHelpers
  def wait_for(timeout: 2)
    deadline = Tarantool::Client::Transport::Deadline.after(timeout)
    until yield
      raise 'condition not met in time' if Tarantool::Client::Transport::Deadline.remaining(deadline).zero?

      sleep 0.01
    end
  end
end
