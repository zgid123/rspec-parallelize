# frozen_string_literal: true

require 'spec_helper'

if ENV['CRASH_WORKER']
  RSpec.describe 'Crashing group' do
    it 'kills its worker' do
      exit!(3)
    end
  end
end
