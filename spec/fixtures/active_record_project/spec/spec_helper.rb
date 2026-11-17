# frozen_string_literal: true

# A Rails-like setup without Rails: ActiveRecord + SQLite + db/schema.rb.
ENV['RAILS_ENV'] = 'test'

require 'active_record'
require 'rspec/parallelize'

root = File.expand_path('..', __dir__)
ActiveRecord::Tasks::DatabaseTasks.root = root
ActiveRecord::Tasks::DatabaseTasks.db_dir = File.join(root, 'db')
ActiveRecord::Tasks::DatabaseTasks.env = 'test'
ActiveRecord::Base.configurations = {
  test: {
    adapter: 'sqlite3',
    database: File.join(ENV.fetch('DB_DIR'), 'test.sqlite3')
  }
}
ActiveRecord::Base.establish_connection
ActiveRecord::Schema.verbose = false
load File.join(root, 'db/schema.rb') # the parent's own database, like maintain_test_schema!

class Widget < ActiveRecord::Base; end

RSpec::Parallelize.configure(workers: 3, threshold: 1)

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
