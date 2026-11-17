# frozen_string_literal: true

module RSpec
  module Parallelize
    # Prepended onto RSpec::Core::Runner. RSpec has already loaded, filtered
    # and ordered the groups by the time `run_specs` is called; we only change
    # who executes them.
    module RunnerExtension
      def run_specs(example_groups)
        config = Parallelize.configuration
        return super unless config.enabled? && !@configuration.dry_run?

        workers = config.worker_count
        count = @world.example_count(example_groups)
        return super if count.zero?

        reason = serial_reason(config, workers, count)
        if reason
          @configuration.reporter.message("rspec-parallelize: running serially (#{reason})")
          return super
        end

        passed = Orchestrator.new(@configuration, example_groups, [workers, example_groups.size].min).run
        exit_code(passed)
      end

      private

      def serial_reason(config, workers, count)
        if workers <= 1
          "workers = #{workers}"
        elsif count < config.threshold
          "#{count} examples is below the threshold of #{config.threshold}"
        elsif !config.fork_supported?
          "fork is not available on #{RUBY_ENGINE}/#{RUBY_PLATFORM}"
        end
      end
    end
  end
end
