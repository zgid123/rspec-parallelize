# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Slow group 5' do
  before(:all) { @setup_pid = Process.pid }

  it 'runs in a single process' do
    sleep 0.3
    File.open(ENV.fetch('EVENTS_FILE'), 'a') { |f| f.puts "example 5 #{Process.pid}" } if ENV['EVENTS_FILE']
    expect(Process.pid).to eq(@setup_pid)
  end

  describe 'generated description' do
    subject { 5 }

    it { is_expected.to eq(5) }
  end
end
