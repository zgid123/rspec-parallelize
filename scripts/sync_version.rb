# frozen_string_literal: true

require 'json'

# Copies the version Changesets wrote into package.json into the files the gem
# reads it from. Run by `pnpm version-packages`, right after `changeset version`.
module SyncVersion
  ROOT = File.expand_path('..', __dir__)

  # Each file that carries the gem's version, and how to set it.
  FILES = {
    'lib/rspec/parallelize/version.rb' => lambda { |text, version|
      replace(text, /VERSION = '[^']*'/, "VERSION = '#{version}'")
    },
    # Bundler records the gem's own version, so the lockfile has to follow.
    'Gemfile.lock' => lambda { |text, version|
      replace(text, /^(\s+rspec-parallelize) \([^)]*\)$/, "\\1 (#{version})")
    }
  }.freeze

  module_function

  # Returns the synced version.
  def sync(root: ROOT)
    version = JSON.parse(File.read(File.join(root, 'package.json'))).fetch('version')

    FILES.each do |path, update|
      file = File.join(root, path)
      File.write(file, update.call(File.read(file), version))
    end

    version
  end

  # A file without a version to replace is a mistake worth stopping for.
  def replace(text, pattern, replacement)
    raise ArgumentError, "No version found for #{pattern.inspect}" unless text.match?(pattern)

    text.gsub(pattern, replacement)
  end
end

puts "Synced rspec-parallelize #{SyncVersion.sync}" if $PROGRAM_NAME == __FILE__
