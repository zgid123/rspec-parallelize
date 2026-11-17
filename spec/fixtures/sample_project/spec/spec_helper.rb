# frozen_string_literal: true

require 'rspec/parallelize'

RSpec::Parallelize.configure(workers: 3, threshold: Integer(ENV.fetch('THRESHOLD', '1')))

RSpec::Parallelize.after_fork do |number|
  File.open(ENV.fetch('EVENTS_FILE'), 'a') { |f| f.puts "after_fork #{number} #{Process.pid}" } if ENV['EVENTS_FILE']
end

RSpec.configure do |config|
  config.order = :random
  config.example_status_persistence_file_path = ENV['STATUS_FILE'] if ENV['STATUS_FILE']
end
