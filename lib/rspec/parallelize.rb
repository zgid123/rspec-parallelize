# frozen_string_literal: true

require 'etc'
require 'rspec/core'
require 'rspec/parallelize/version'
require 'rspec/parallelize/configuration'
require 'rspec/parallelize/active_record'
require 'rspec/parallelize/progress_line'
require 'rspec/parallelize/serializer'
require 'rspec/parallelize/worker_reporter'
require 'rspec/parallelize/worker'
require 'rspec/parallelize/orchestrator'
require 'rspec/parallelize/runner_extension'

module RSpec
  # Runs plain `rspec` in parallel: the suite boots once, workers are forked
  # from it, and top-level example groups are handed out from a shared queue.
  #
  #   # spec/spec_helper.rb
  #   RSpec::Parallelize.configure
  module Parallelize
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      # Enables parallel runs. `workers` is an Integer, :half_of_processors
      # (the default) or :number_of_processors; runs with fewer than
      # `threshold` examples stay serial.
      def configure(workers: Configuration::DEFAULT_WORKERS, threshold: Configuration::DEFAULT_THRESHOLD)
        configuration.enable(workers: workers, threshold: threshold)
      end

      # Runs in each worker right after it is forked, before any `before(:suite)`
      # hook. Receives the 0-based worker number.
      def after_fork(&block)
        configuration.after_fork_hooks << block
      end

      # Runs in each worker after its last group and `after(:suite)` hooks.
      def before_exit(&block)
        configuration.before_exit_hooks << block
      end
    end
  end
end

RSpec::Core::Runner.prepend(RSpec::Parallelize::RunnerExtension)

# Keep our frames out of failure backtraces, like RSpec does for its own.
RSpec.configuration.backtrace_exclusion_patterns << %r{/lib/rspec/parallelize(\.rb|/)}
