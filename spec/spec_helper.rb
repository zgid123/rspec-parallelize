# frozen_string_literal: true

require 'open3'
require 'io/console'
require 'pty'
require 'tmpdir'
require 'active_record'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
