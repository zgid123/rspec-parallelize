# frozen_string_literal: true

module RSpec
  module Parallelize
    # Stand-in for an exception whose class can't be found in the parent.
    class RemoteException < StandardError; end

    # Converts example results and exceptions into plain data that can cross
    # the worker -> parent pipe, and back again.
    module Serializer
      module_function

      def dump_result(example)
        result = example.execution_result
        {
          status: result.status,
          started_at: result.started_at,
          finished_at: result.finished_at,
          run_time: result.run_time,
          pending_message: result.pending_message,
          pending_fixed: result.pending_fixed,
          exception: dump_exception(result.exception),
          pending_exception: dump_exception(result.pending_exception),
          # Descriptions of `it { is_expected.to ... }` are generated at run time.
          description: example.metadata[:description],
          full_description: example.metadata[:full_description]
        }
      end

      def load_result(example, data)
        result = example.execution_result

        %i[status started_at finished_at run_time pending_message pending_fixed].each do |key|
          result.public_send(:"#{key}=", data[key])
        end

        result.exception = load_exception(data[:exception])
        result.pending_exception = load_exception(data[:pending_exception])
        example.instance_variable_set(:@exception, result.exception)
        example.metadata[:description] = data[:description]
        example.metadata[:full_description] = data[:full_description]
      end

      def dump_exception(exception)
        return nil if exception.nil?

        {
          marshaled: Marshal.dump(exception)
        }
      rescue TypeError, ArgumentError
        {
          class_name: exception.class.name,
          message: safe_message(exception),
          backtrace: exception.backtrace,
          cause: dump_exception(exception.cause)
        }
      end

      def load_exception(data)
        return nil if data.nil?
        return Marshal.load(data[:marshaled]) if data[:marshaled] # rubocop:disable Security/MarshalLoad

        rebuild_exception(data)
      end

      # Recreates an exception of the original class without calling its
      # (possibly picky) initializer, so formatters print the real class name.
      def rebuild_exception(data)
        klass = Object.const_get(data[:class_name].to_s) rescue nil # rubocop:disable Style/RescueModifier
        klass = RemoteException unless klass.is_a?(Class) && klass <= Exception

        message = klass == RemoteException ? "#{data[:class_name]}: #{data[:message]}" : data[:message]
        exception = klass.allocate
        Exception.instance_method(:initialize).bind_call(exception, message)
        exception.define_singleton_method(:message) { message }
        exception.define_singleton_method(:to_s) { message }
        exception.set_backtrace(data[:backtrace]) if data[:backtrace]
        cause = load_exception(data[:cause])
        exception.define_singleton_method(:cause) { cause }
        exception
      end

      def safe_message(exception)
        exception.message.to_s
      rescue Exception => e # rubocop:disable Lint/RescueException
        "#{exception.class} (message raised #{e.class})"
      end
    end
  end
end
