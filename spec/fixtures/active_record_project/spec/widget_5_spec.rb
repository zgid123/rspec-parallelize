# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Widgets 5' do
  it "writes to this worker's own database" do
    Widget.create!(name: 'widget 5')
    sleep 0.2
    database = ActiveRecord::Base.connection_db_config.database

    File.open(ENV.fetch('EVENTS_FILE'), 'a') { |f| f.puts "#{Process.pid} #{database}" }

    expect(Widget.pluck(:name)).to eq(['widget 5'])
  end
end
