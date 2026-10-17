# frozen_string_literal: true

# Timing helpers shared by the benchmark scripts: per-request durations, percentiles, one table line per case.
module Measure
  module_function

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Durations in seconds of each call of the block, run `iterations` times.
  def durations(iterations)
    Array.new(iterations) do |index|
      started = now
      yield index

      now - started
    end
  end

  # The same in `threads` threads, `iterations` calls in total; the block gets the global index.
  def threaded_durations(iterations, threads:)
    per_thread = iterations / threads
    workers = Array.new(threads) do |thread|
      Thread.new { durations(per_thread) { |index| yield (thread * per_thread) + index } }
    end

    workers.flat_map(&:value)
  end

  def percentile(sorted, fraction) = sorted[((sorted.size - 1) * fraction).round]

  def summary(durations, elapsed)
    sorted = durations.sort

    { rate: durations.size / elapsed, p50: percentile(sorted, 0.5), p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99) }
  end

  # Runs the case once to warm up, then for the record.
  def report(name, iterations, threads: 1, &)
    2.times { |pass| run_case(name, iterations, threads, record: pass == 1, &) }
  end

  def run_case(name, iterations, threads, record:, &)
    started = now
    taken = threads == 1 ? durations(iterations, &) : threaded_durations(iterations, threads:, &)
    return unless record

    line(name, summary(taken, now - started))
  end

  def line(name, summary)
    puts format('%-24<name>s %9<rate>.0f req/s  p50 %6<p50>.3f ms  p95 %6<p95>.3f ms  p99 %6<p99>.3f ms',
                name:, rate: summary[:rate], p50: summary[:p50] * 1000, p95: summary[:p95] * 1000,
                p99: summary[:p99] * 1000)
  end

  def environment(client_version:, server_version:, uri:)
    puts "#{client_version} | tarantool #{server_version} at #{uri} | #{RUBY_DESCRIPTION} | #{RbConfig::CONFIG['host']}"
  end
end
