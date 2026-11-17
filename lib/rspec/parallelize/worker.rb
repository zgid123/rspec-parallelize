# frozen_string_literal: true

module RSpec
  module Parallelize
    # The forked side. Pulls top-level group ids from the parent, runs them
    # against its own (copy-on-write) copy of the loaded suite, and sends the
    # recorded reporter events back.
    #
    # Protocol, one Marshal'd value per message:
    #   parent -> worker: group id to run, or nil to stop
    #   worker -> parent: [:result, group_id, events] after each group,
    #                     [:done, events] once suite hooks have finished
    class Worker
      def initialize(number, configuration, groups_by_id, commands, results)
        @number = number
        @configuration = configuration
        @groups_by_id = groups_by_id
        @commands = commands
        @results = results
      end

      def run
        setup_environment
        @reporter = install_reporter
        run_after_fork_hooks
        @configuration.with_suite_hooks { serve }
        Parallelize.configuration.before_exit_hooks.each { |hook| hook.call(@number) }
        send_message([:done, @reporter.drain])
        finish(0)
      rescue EOFError, Errno::EPIPE
        finish(0) # parent went away
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn "rspec-parallelize: worker #{@number} failed: #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}"
        finish(1)
      end

      private

      # Databases first, so user hooks and before(:suite) can already use them.
      def run_after_fork_hooks
        ActiveRecordIntegration.after_fork(@number)
        Parallelize.configuration.after_fork_hooks.each { |hook| hook.call(@number) }
      end

      def serve
        send_message([:ready, @reporter.drain])

        while (group_id = Marshal.load(@commands)) # rubocop:disable Security/MarshalLoad
          @groups_by_id.fetch(group_id).run(@reporter)
          send_message([:result, group_id, @reporter.drain])
        end
      end

      # TEST_ENV_NUMBER follows parallel_tests: "" for the first worker, then
      # "2", "3", ... so existing database.yml templates keep working.
      def setup_environment
        ENV['TEST_ENV_NUMBER'] = @number.zero? ? '' : (@number + 1).to_s
        ENV['PARALLEL_WORKER_NUMBER'] = @number.to_s
        RSpec.world.wants_to_quit = false
      end

      def install_reporter
        reporter = WorkerReporter.new(@configuration)
        @configuration.instance_variable_set(:@reporter, reporter)
        reporter
      end

      # Skips at_exit handlers inherited from the parent (RSpec autorun etc.).
      def finish(status)
        $stdout.flush
        $stderr.flush
        exit!(status)
      end

      def send_message(message)
        Marshal.dump(message, @results)
        @results.flush
      end
    end
  end
end
