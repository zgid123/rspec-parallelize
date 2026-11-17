# rspec-parallelize

Run plain `rspec` in parallel, the way Rails' minitest `parallelize` does.

> Work in progress.

## Development

```sh
bundle install
bundle exec rake          # specs + RuboCop
bundle exec rspec         # specs only
bundle exec rubocop -a    # lint, applying safe fixes
```

### Releasing

Versions are managed with [Changesets](https://github.com/changesets/changesets);
`package.json` holds the version and `scripts/sync_version.rb` copies it into
`lib/rspec/parallelize/version.rb` and `Gemfile.lock`.

1. `pnpm install`, then `pnpm set-release` in your branch to describe the
   change (patch / minor / major). Commit the generated `.changeset/*.md`.
2. Once merged to `main`, the Release workflow opens a "Version Packages" PR
   (version bump + `CHANGELOG.md`).
3. Merging that PR tags `vX.Y.Z`, creates the GitHub release and publishes the
   gem to RubyGems via trusted publishing.
