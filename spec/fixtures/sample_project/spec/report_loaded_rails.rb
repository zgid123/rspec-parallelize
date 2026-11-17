# frozen_string_literal: true

# Records, from every worker, whether any Rails code got loaded.
RSpec.configure do |config|
  config.after(:suite) do
    loaded = $LOADED_FEATURES.grep(%r{/(active_record|active_support)/})
    loaded = loaded.reject { |f| f.include?('rspec/parallelize') }
    line = loaded.empty? ? 'rails not loaded' : "rails loaded: #{loaded.first}"

    File.open(ENV.fetch('EVENTS_FILE'), 'a') { |f| f.puts(line) }
  end
end
