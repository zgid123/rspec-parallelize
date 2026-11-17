# frozen_string_literal: true

require 'rspec/parallelize'

RSpec.describe RSpec::Parallelize::Configuration do
  subject(:config) { described_class.new }

  around do |example|
    original = ENV.delete('PARALLEL_WORKERS')
    example.run
  ensure
    original ? ENV['PARALLEL_WORKERS'] = original : ENV.delete('PARALLEL_WORKERS')
  end

  before { allow(Etc).to receive(:nprocessors).and_return(12) }

  describe '#worker_count' do
    it 'defaults to half of the processors' do
      expect(config.worker_count).to eq(6)
    end

    it 'never defaults to fewer than 2 workers' do
      allow(Etc).to receive(:nprocessors).and_return(2)

      expect(config.worker_count).to eq(2)
    end

    it 'uses every processor when asked to' do
      config.enable(workers: :number_of_processors, threshold: 50)

      expect(config.worker_count).to eq(12)
    end

    it 'accepts an explicit number' do
      config.enable(workers: 3, threshold: 50)

      expect(config.worker_count).to eq(3)
    end

    it 'lets PARALLEL_WORKERS override the configured value' do
      config.enable(workers: 3, threshold: 50)
      ENV['PARALLEL_WORKERS'] = '16'

      expect(config.worker_count).to eq(16)
    end
  end
end
