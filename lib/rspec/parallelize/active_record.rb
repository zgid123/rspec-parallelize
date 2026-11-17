# frozen_string_literal: true

module RSpec
  module Parallelize
    # Gives every worker its own test database(s), the way Rails' minitest
    # `parallelize` does: `myapp_test` becomes `myapp_test_0`, `myapp_test_1`,
    # ... each rebuilt from db/schema.rb (or structure.sql) at the start of the
    # run. Delegates to Rails' own ActiveRecord::TestDatabases.
    #
    # Only active when ActiveRecord is loaded, and honours
    # `config.active_support.parallelize_test_databases = false`.
    module ActiveRecordIntegration
      module_function

      def enabled?
        return false unless defined?(::ActiveRecord::Base)
        return true unless ::ActiveSupport.respond_to?(:parallelize_test_databases)

        ::ActiveSupport.parallelize_test_databases != false
      end

      # Forked children must not share the parent's database sockets.
      def before_fork
        return unless enabled?

        require 'active_record/test_databases'
        ::ActiveRecord::Base.connection_handler.clear_all_connections!
      end

      def after_fork(worker_number)
        return unless enabled?

        ::ActiveRecord::TestDatabases.create_and_load_schema(
          worker_number, env_name: ::ActiveRecord::ConnectionHandling::DEFAULT_ENV.call
        )
      end
    end
  end
end
