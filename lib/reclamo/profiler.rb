# frozen_string_literal: true

module Reclamo
  class Profiler
    DEFAULT_MAX_SAMPLES = 10_000

    def initialize(server, max_samples: DEFAULT_MAX_SAMPLES)
      @data = {}
      @mutex = Mutex.new
      @max_samples = max_samples
      attach(server)
    end

    def [](method_name)
      entry_copy = @mutex.synchronize do
        entry = @data[method_name]
        return nil unless entry

        snapshot_entry(entry)
      end
      build_stats(entry_copy)
    end

    def tracked_methods
      @mutex.synchronize { @data.keys.sort }
    end
    alias methods tracked_methods

    def stats
      entries = @mutex.synchronize { @data.to_h { |name, entry| [name, snapshot_entry(entry)] } }
      entries.transform_values { |entry| build_stats(entry) }
    end

    def reset
      @mutex.synchronize { @data.clear }
    end

    private

    def attach(server)
      server.on(:response) { |request, _result, duration| record(request.method_name, duration) }
      server.on(:error) { |request, _error, duration| record(request.method_name, duration) }
    end

    def record(method_name, duration)
      @mutex.synchronize do
        entry = (@data[method_name] ||= { count: 0, total: 0.0, min: Float::INFINITY, max: 0.0, durations: [] })
        entry[:count] += 1
        entry[:total] += duration
        entry[:min] = duration if duration < entry[:min]
        entry[:max] = duration if duration > entry[:max]
        entry[:durations] << duration
        entry[:durations].shift if entry[:durations].size > @max_samples
      end
    end

    def snapshot_entry(entry)
      { count: entry[:count], total: entry[:total], min: entry[:min], max: entry[:max],
        durations: entry[:durations].dup }
    end

    def build_stats(entry)
      sorted = entry[:durations].sort
      timing_stats(entry).merge(percentile_stats(sorted))
    end

    def timing_stats(entry)
      avg = entry[:count].zero? ? 0.0 : entry[:total] / entry[:count]
      { count: entry[:count], total: entry[:total].round(6),
        min: entry[:min].round(6), max: entry[:max].round(6), avg: avg.round(6) }
    end

    def percentile_stats(sorted)
      { p50: percentile(sorted, 50), p95: percentile(sorted, 95), p99: percentile(sorted, 99) }
    end

    def percentile(sorted, pct)
      return 0.0 if sorted.empty?

      k = ((pct / 100.0) * sorted.size).ceil - 1
      sorted[[k, 0].max].round(6)
    end
  end
end
