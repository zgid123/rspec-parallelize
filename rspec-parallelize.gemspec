# frozen_string_literal: true

require_relative 'lib/rspec/parallelize/version'

Gem::Specification.new do |spec|
  spec.name = 'rspec-parallelize'
  spec.version = RSpec::Parallelize::VERSION
  spec.authors = ['Alpha']
  spec.summary = "Run plain `rspec` in parallel, the way Rails' minitest `parallelize` does."
  spec.description = <<~DESC
    Boots your suite once, forks workers, and feeds them top-level example groups
    from a shared queue. Results are replayed into RSpec's own reporter, so every
    formatter, --only-failures and --seed keep working.
  DESC
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'rspec-core', '>= 3.12', '< 4'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
