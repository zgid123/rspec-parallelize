# frozen_string_literal: true

module RSpec
  module Parallelize
    # Installed as the reporter inside a worker. Instead of notifying
    # formatters it records each event as plain data; the parent replays the
    # events into the real reporter (see Orchestrator#replay).
    class WorkerReporter < RSpec::Core::Reporter
      attr_reader :events

      def initialize(configuration)
        super

        @events = []
      end

      def drain
        drained = @events
        @events = []
        drained
      end

      def example_group_started(group)
        @events << [:example_group_started, group.id]
      end

      def example_group_finished(group)
        @events << [:example_group_finished, group.id]
      end

      def example_started(example)
        @examples << example
        @events << [:example_started, example.id]
      end

      # Called once the status is recorded, before passed/failed/pending.
      def example_finished(example)
        @events << [:example_finished, example.id, Serializer.dump_result(example)]
      end

      def example_passed(example)
        @events << [:example_passed, example.id]
      end

      def example_failed(example)
        @failed_examples << example
        @events << [:example_failed, example.id]
      end

      def example_pending(example)
        @pending_examples << example
        @events << [:example_pending, example.id]
      end

      def message(message)
        @events << [:message, message.to_s]
      end

      def deprecation(hash)
        @events << [:deprecation, hash.transform_values { |v| v.is_a?(String) || v.nil? ? v : v.to_s }]
      end

      # Custom events whose payload can't cross the pipe are dropped.
      def publish(event, options = {})
        Marshal.dump(options)
        @events << [:publish, event, options]
      rescue TypeError
        nil
      end

      def notify_non_example_exception(exception, context_description)
        @configuration.world.non_example_failure = true
        @events << [:non_example_exception, Serializer.dump_exception(exception), context_description]
      end
    end
  end
end
