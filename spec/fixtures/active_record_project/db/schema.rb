# frozen_string_literal: true

ActiveRecord::Schema.define(version: 1) do
  create_table :widgets, force: true do |t|
    t.string :name, null: false
  end
end
