# frozen_string_literal: true

module RSpec
  module Parallelize
    # The parent side. Forks workers, hands out top-level groups from a queue
    # as workers become free, and replays the events they send back into
    # RSpec's real reporter so every formatter sees a normal run.
    class Orchestrator
      WorkerState = Struct.new(:number, :pid, :commands, :results, :group_id, :done, keyword_init: true)

      # How often the live progress line is redrawn while nothing arrives.
      PROGRESS_INTERVAL = 1

      def initialize(configuration, example_groups, worker_count)
        @configuration = configuration
        @example_groups = example_groups
        @worker_count = worker_count
        @queue = example_groups.map(&:id)
        @workers = {}
        @stats = Hash.new { |h, number| h[number] = { pids: [], groups: 0, examples: 0 } }
        @progress = ProgressLine.new(configuration.output_stream)
        index_suite
      end

      # Returns true when every example passed.
      def run
        @example_count = RSpec.world.example_count(@example_groups)
        @configuration.reporter.report(@example_count) do |reporter|
          @reporter = reporter
          @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          announce
          @worker_count.times { |number| spawn_worker(number) }
          process_messages until @workers.empty?
          @progress.stop
          report_stats
          reporter.failed_examples.empty?
        end
      ensure
        @progress.stop
        shutdown
      end

      private

      def index_suite
        @top_groups = {}
        @groups = {}
        @examples = {}
        @example_groups.each do |top|
          @top_groups[top.id] = top
          top.descendants.each do |group|
            @groups[group.id] = group
            group.examples.each { |example| @examples[example.id] = example }
          end
        end
      end

      def spawn_worker(number)
        commands_r, commands_w = IO.pipe
        results_r, results_w = IO.pipe
        [commands_r, commands_w, results_r, results_w].each(&:binmode)
        parent_ends = @workers.values.flat_map { |w| [w.commands, w.results] }
        ActiveRecordIntegration.before_fork

        pid = Process.fork do
          # Drop every parent-side pipe end so a worker's EOF is detected even
          # while siblings are still running.
          (parent_ends + [commands_w, results_r]).each(&:close)
          Worker.new(number, @configuration, @top_groups, commands_r, results_w).run
        end

        commands_r.close
        results_w.close
        @stats[number][:pids] << pid
        @workers[results_r] = WorkerState.new(number: number, pid: pid, commands: commands_w, results: results_r)
      end

      def announce
        databases = ActiveRecordIntegration.enabled? ? ', each with its own test database' : ''
        @reporter.message("rspec-parallelize: running #{@example_count} examples in #{@example_groups.size} groups " \
                          "using #{@worker_count} processes#{databases} (parent pid #{Process.pid})")
        @progress.start
        draw_progress
      end

      def draw_progress
        finished = @stats.each_value.sum { |stat| stat[:examples] }
        busy = @workers.each_value.count(&:group_id)
        failures = @reporter.failed_examples.size
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at).round

        @progress.update(
          "rspec-parallelize: #{finished}/#{@example_count} examples · " \
          "#{failures} #{failures == 1 ? 'failure' : 'failures'} · " \
          "#{busy}/#{@worker_count} workers busy · #{elapsed}s"
        )
      end

      def report_stats
        lines = @stats.sort.map do |number, stat|
          format('  worker %<n>d (pid %<pids>s): %<groups>d groups, %<examples>d examples',
                 n: number, pids: stat[:pids].join(', '), groups: stat[:groups], examples: stat[:examples])
        end
        @reporter.message("\nrspec-parallelize: work per process\n#{lines.join("\n")}")
      end

      def process_messages
        ready, = IO.select(@workers.keys, nil, nil, PROGRESS_INTERVAL)
        Array(ready).each do |io|
          worker = @workers.fetch(io)
          message = begin
            Marshal.load(io) # rubocop:disable Security/MarshalLoad
          rescue EOFError
            nil
          end

          message ? handle(worker, message) : worker_exited(worker)
        end
        draw_progress
      end

      def handle(worker, message)
        case message.first
        when :ready
          replay(message[1])
          dispatch(worker)
        when :result
          replay(message[2])
          @stats[worker.number][:groups] += 1
          @stats[worker.number][:examples] += message[2].count { |event| event.first == :example_finished }
          worker.group_id = nil
          dispatch(worker)
        when :done
          replay(message[1])
          worker.done = true
        end
      end

      def dispatch(worker)
        @queue.clear if RSpec.world.wants_to_quit || @reporter.fail_fast_limit_met?
        worker.group_id = @queue.shift
        Marshal.dump(worker.group_id, worker.commands)
        worker.commands.flush
      rescue Errno::EPIPE
        nil # the worker died; its EOF is handled in #worker_exited
      end

      def worker_exited(worker)
        @workers.delete(worker.results)
        worker.results.close
        worker.commands.close unless worker.commands.closed?
        _, status = Process.wait2(worker.pid)
        return if worker.done

        report_crash(worker, status)
        # Only replace workers that got as far as running a group; one dying
        # during boot (e.g. a failing after_fork hook) would just die again.
        if worker.group_id && !@queue.empty?
          spawn_worker(worker.number)
        elsif @workers.empty? && !@queue.empty?
          report_unrun_groups
        end
      end

      def report_unrun_groups
        error = RuntimeError.new("#{@queue.size} example group(s) were not run because every worker crashed")
        error.set_backtrace([])
        @reporter.notify_non_example_exception(error, 'rspec-parallelize')
        @queue.clear
      end

      def report_crash(worker, status)
        what = worker.group_id ? "while running #{describe_group(worker.group_id)}" : 'before finishing'
        error = RuntimeError.new("Worker #{worker.number} crashed #{what} (#{status.inspect})")
        # Point at the crashed group's `describe` line so RSpec shows it instead
        # of "Unable to find matching line from backtrace".
        location = worker.group_id && @top_groups.fetch(worker.group_id).metadata[:location]
        error.set_backtrace(location ? ["#{location}:in '<top (required)>'"] : [])
        @reporter.notify_non_example_exception(error, "rspec-parallelize worker #{worker.number}")
      end

      def describe_group(group_id)
        group = @top_groups.fetch(group_id)
        "#{group.metadata[:rerun_file_path] || group.file_path} (#{group.description})"
      end

      def replay(events)
        events.each { |name, *args| replay_event(name, *args) }
      end

      def replay_event(name, *args)
        case name
        when :example_group_started, :example_group_finished
          @reporter.public_send(name, @groups.fetch(args[0]))
        when :example_started, :example_passed, :example_failed, :example_pending
          @reporter.public_send(name, @examples.fetch(args[0]))
        when :example_finished
          example = @examples.fetch(args[0])
          Serializer.load_result(example, args[1])
          @reporter.example_finished(example)
        when :non_example_exception
          @reporter.notify_non_example_exception(Serializer.load_exception(args[0]), args[1])
        else # :message, :deprecation, :publish
          @reporter.public_send(name, *args)
        end
      end

      # Reached on normal completion and on interrupts: never leave orphans.
      # Signal every worker before waiting on any, so they stop in parallel.
      def shutdown
        @workers.each_value do |worker|
          Process.kill(:TERM, worker.pid)
        rescue Errno::ESRCH
          nil
        end
        @workers.each_value do |worker| # rubocop:disable Style/CombinableLoops
          Process.wait(worker.pid)
        rescue Errno::ECHILD
          nil
        end
        @workers.clear
      end
    end
  end
end
