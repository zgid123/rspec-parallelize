# frozen_string_literal: true

module RSpec
  module Parallelize
    # Settings from RSpec::Parallelize.configure and the PARALLEL_WORKERS env var.
    class Configuration
      DEFAULT_THRESHOLD = 50
      # Leaves half the cores free so the machine stays usable during a local
      # run; CI can ask for more with PARALLEL_WORKERS or `workers:`.
      DEFAULT_WORKERS = :half_of_processors

      attr_reader :after_fork_hooks, :before_exit_hooks, :threshold

      def initialize
        @enabled = false
        @workers = DEFAULT_WORKERS
        @threshold = DEFAULT_THRESHOLD
        @after_fork_hooks = []
        @before_exit_hooks = []
      end

      def enable(workers:, threshold:)
        @enabled = true
        @workers = workers
        @threshold = Integer(threshold)
      end

      def enabled?
        @enabled
      end

      # PARALLEL_WORKERS wins over the configured value, like Rails.
      def worker_count
        value = ENV.fetch('PARALLEL_WORKERS', '').strip

        value = @workers if value.empty?

        case value.to_s
        when 'number_of_processors' then Etc.nprocessors
        when 'half_of_processors' then [Etc.nprocessors / 2, 2].max
        else Integer(value)
        end
      end

      def fork_supported?
        Process.respond_to?(:fork) && RUBY_ENGINE == 'ruby'
      end
    end
  end
end
