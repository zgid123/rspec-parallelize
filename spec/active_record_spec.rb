# frozen_string_literal: true

# Runs spec/fixtures/active_record_project, a Rails-like ActiveRecord + SQLite
# suite, and checks every worker gets its own freshly loaded database.
RSpec.describe 'ActiveRecord per-worker databases', :aggregate_failures do
  let(:project) { File.expand_path('fixtures/active_record_project', __dir__) }
  let(:lib) { File.expand_path('../lib', __dir__) }
  let(:tmp) { Dir.mktmpdir }
  let(:events_file) { File.join(tmp, 'events.log') }

  after { FileUtils.remove_entry(tmp) }

  def run_rspec(env: {})
    env = { 'EVENTS_FILE' => events_file, 'DB_DIR' => tmp }.merge(env)
    out, status = Open3.capture2e(env, RbConfig.ruby, '-I', lib, '-S', 'rspec', chdir: project)
    [out, status.exitstatus]
  end

  def databases_by_pid
    rows = File.readlines(events_file, chomp: true).map(&:split)
    rows.group_by(&:first).transform_values { |pid_rows| pid_rows.map(&:last).uniq }
  end

  it 'creates and loads a separate database for each worker' do
    out, status = run_rspec

    expect(status).to eq(0), out
    expect(out).to include('using 3 processes, each with its own test database')
    expect(out).to include('6 examples, 0 failures')

    databases = databases_by_pid.values.flatten
    expect(databases.uniq.size).to eq(databases_by_pid.size)
    expect(databases.map { |db| File.basename(db) }).to all(match(/\Atest\.sqlite3_[0-2]\z/))
  end

  it 'rebuilds the worker databases from the schema on the next run' do
    run_rspec
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: File.join(tmp, 'test.sqlite3_0'))
    ActiveRecord::Base.connection.execute("INSERT INTO widgets (name) VALUES ('left over')")
    ActiveRecord::Base.remove_connection

    out, status = run_rspec
    expect(status).to eq(0), out
  end

  it 'keeps using the single test database when running serially' do
    out, status = run_rspec(env: { 'PARALLEL_WORKERS' => '1' })

    expect(status).to eq(0), out
    expect(databases_by_pid.values.flatten.map { |db| File.basename(db) }.uniq).to eq(['test.sqlite3'])
  end
end
