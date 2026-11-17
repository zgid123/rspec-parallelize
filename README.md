# rspec-parallelize

Run plain `rspec` in parallel, the way Rails' minitest `parallelize` does.

Your suite boots **once**, then workers are forked from it (sharing memory
copy-on-write) and pull top-level example groups from a shared queue. Results
are replayed into RSpec's own reporter, so the output looks like a normal run
and every formatter, `--seed`, `--only-failures` and CI reporter keeps working.
No extra binary, no `rake parallel:setup`.

## Usage

```ruby
# Gemfile
gem "rspec-parallelize", group: :test

# spec/spec_helper.rb (or spec/rails_helper.rb) — once, for the whole suite
require "rspec/parallelize"
RSpec::Parallelize.configure
```

Then run `rspec` as usual.

| Option / env | Effect |
|---|---|
| `workers:` (default `:half_of_processors`) | Integer, `:half_of_processors` (half the CPU cores, min 2 — keeps your laptop usable) or `:number_of_processors` |
| `threshold:` (default 50) | Runs with fewer examples stay serial, so a single spec is still instant |
| `RSPEC_PARALLELIZE_PROGRESS=0` | Hides the live progress line (it is already off in CI and when output is piped) |
| `PARALLEL_WORKERS=8` | Overrides `workers:` (e.g. more workers on CI); `PARALLEL_WORKERS=1` disables parallelism |

### Per-worker setup

```ruby
RSpec::Parallelize.after_fork do |worker_number|  # 0-based
  Redis.current.select(worker_number)
end

RSpec::Parallelize.before_exit do |worker_number|
  # clean up per-worker resources
end
```

Each worker also gets `TEST_ENV_NUMBER` (`""`, `"2"`, `"3"`, … like
parallel_tests), so existing `database.yml` templates keep working.

## Rails / ActiveRecord

If ActiveRecord is loaded, every worker automatically gets its own test
database, just like Rails' minitest `parallelize`: `myapp_test` becomes
`myapp_test_0`, `myapp_test_1`, ..., each rebuilt from `db/schema.rb` (or
`structure.sql`) at the start of the run. Nothing to create by hand, no
`TEST_ENV_NUMBER` needed in `database.yml`. It uses Rails' own
`ActiveRecord::TestDatabases`, and respects
`config.active_support.parallelize_test_databases = false`.

In a plain Ruby project none of this loads; no Rails code is required.

## How it works

- A **unit of work** is a top-level example group, so `before(:all)` hooks run
  exactly once, as they do serially.
- `before(:suite)` / `after(:suite)` hooks run in **each worker**, so per-worker
  resources (databases etc.) get set up and cleaned up.
- If a worker crashes, its group is reported as an error, a replacement worker
  is forked, and the run exits non-zero.
- Requires `fork` (MRI on Linux/macOS). Elsewhere it warns and runs serially.

## Status

Early. Planned next: slowest-groups-first scheduling from recorded runtimes,
and SimpleCov merging.

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
