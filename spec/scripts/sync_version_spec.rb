# frozen_string_literal: true

require_relative '../../scripts/sync_version'

RSpec.describe SyncVersion do
  let(:root) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(root, 'lib/rspec/parallelize'))
    File.write(File.join(root, 'package.json'), JSON.generate(name: 'rspec-parallelize', version: '1.2.3'))
    File.write(File.join(root, 'lib/rspec/parallelize/version.rb'), "    VERSION = '0.0.0'\n")
    File.write(File.join(root, 'Gemfile.lock'), <<~LOCK)
      PATH
        remote: .
        specs:
          rspec-parallelize (0.0.0)
            rspec-core (>= 3.12, < 4)

      CHECKSUMS
        rspec-parallelize (0.0.0)
        rspec-core (3.13.7)
    LOCK
  end

  after { FileUtils.remove_entry(root) }

  def read(path)
    File.read(File.join(root, path))
  end

  it 'copies the package.json version into version.rb and Gemfile.lock', :aggregate_failures do
    expect(described_class.sync(root: root)).to eq('1.2.3')

    expect(read('lib/rspec/parallelize/version.rb')).to eq("    VERSION = '1.2.3'\n")
    expect(read('Gemfile.lock').scan(/rspec-parallelize \(([^)]*)\)/).flatten).to eq(%w[1.2.3 1.2.3])
    expect(read('Gemfile.lock')).to include('rspec-core (3.13.7)')
  end

  it 'stops when a file has no version to replace' do
    File.write(File.join(root, 'Gemfile.lock'), "GEM\n")

    expect { described_class.sync(root: root) }.to raise_error(ArgumentError, /No version found/)
  end
end
