# frozen_string_literal: true

# Runs the suite in spec/fixtures/sample_project through the real `rspec`
# executable and checks what a user would see.
RSpec.describe 'rspec-parallelize end to end', :aggregate_failures do
  let(:project) { File.expand_path('fixtures/sample_project', __dir__) }
  let(:lib) { File.expand_path('../lib', __dir__) }
  let(:tmp) { Dir.mktmpdir }
  let(:events_file) { File.join(tmp, 'events.log') }

  after { FileUtils.remove_entry(tmp) }

  def run_rspec(*args, env: {})
    env = { 'EVENTS_FILE' => events_file }.merge(env)
    command = [RbConfig.ruby, '-I', lib, '-S', 'rspec', *args]
    out, status = Open3.capture2e(env, *command, chdir: project)
    [out, status.exitstatus]
  end

  # Runs rspec attached to a 24x100 pseudo-terminal, like a developer's shell.
  def run_rspec_in_terminal(env: {})
    env = { 'EVENTS_FILE' => events_file, 'CI' => nil }.merge(env)
    command = [RbConfig.ruby, '-I', lib, '-S', 'rspec']
    PTY.open do |terminal, child_side|
      terminal.winsize = [24, 100] # sized before rspec starts and reads it
      pid = Process.spawn(env, *command, chdir: project, in: child_side, out: child_side, err: child_side)
      child_side.close
      read_until_closed(terminal).tap { Process.wait(pid) }
    end
  end

  def read_until_closed(terminal)
    output = +''
    loop { output << terminal.readpartial(4096) }
  rescue EOFError, Errno::EIO # Linux raises EIO once the child closes the terminal
    output.force_encoding(Encoding::UTF_8)
  end

  def events
    File.exist?(events_file) ? File.readlines(events_file, chomp: true) : []
  end

  it 'pins a live progress line to the bottom of an interactive terminal' do
    out = run_rspec_in_terminal

    expect(out).to include("\e[1;23r") # rows 1-23 scroll, row 24 holds the status
    expect(out).to match(%r{rspec-parallelize: \d+/16 examples · \d+ failures? · \d/3 workers busy · \d+s})
    expect(out).to include('rspec-parallelize: 16/16 examples · 2 failures')
    expect(out).to include("\e[r") # scroll region restored at the end
    expect(out).to include('16 examples, 2 failures, 1 pending')
  end

  it 'leaves the progress line out when output is not a terminal' do
    out, = run_rspec

    expect(out).not_to include("\e[")
    expect(out).not_to include('workers busy')
  end

  it 'leaves the progress line out when RSPEC_PARALLELIZE_PROGRESS=0' do
    out = run_rspec_in_terminal(env: { 'RSPEC_PARALLELIZE_PROGRESS' => '0' })

    expect(out).not_to include('workers busy')
    expect(out).to include('16 examples, 2 failures, 1 pending')
  end

  it 'runs top-level groups across forked workers and reports one normal summary' do
    out, status = run_rspec

    expect(out).to include('16 examples, 2 failures, 1 pending')
    expect(status).to eq(1)
    expect(out).to include('rspec-parallelize: running 16 examples in 7 groups using 3 processes (parent pid')
    expect(out).to match(/worker 0 \(pid \d+\): \d+ groups, \d+ examples/)
    expect(events.grep(/\Aafter_fork/).map { |e| e.split[1] }).to contain_exactly('0', '1', '2')
    expect(events.grep(/\Aexample/).map { |e| e.split.last }.uniq.size).to be > 1
  end

  it 'never loads Rails in a plain Ruby project' do
    out, = run_rspec('--require', './spec/report_loaded_rails')

    expect(out).not_to include('each with its own test database')
    expect(events.grep(/\Arails/).uniq).to eq(['rails not loaded'])
  end

  it 'replays failures, pending examples and generated descriptions into the formatter' do
    out, = run_rspec('--format', 'documentation')

    expect(out).to include('expected: 3', 'ArgumentError:', 'bad argument', 'PENDING: not done yet')
    expect(out).to include('is expected to eq 4')
    expect(out).to include('rspec ./spec/mixed_spec.rb:6 # Mixed results fails with an expectation')
    expect(out).not_to include('lib/rspec/parallelize')
  end

  it 'is faster than running serially' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    run_rspec('--pattern', 'spec/slow_*_spec.rb')
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Six groups sleep 0.3s each: ~1.8s serially, ~0.6s on three workers.
    expect(elapsed).to be < 1.6
  end

  it 'runs serially when PARALLEL_WORKERS=1' do
    out, status = run_rspec(env: { 'PARALLEL_WORKERS' => '1' })

    expect(out).to include('16 examples, 2 failures, 1 pending')
    expect(status).to eq(1)
    expect(out).to include('rspec-parallelize: running serially (workers = 1)')
    expect(events.grep(/\Aafter_fork/)).to be_empty
  end

  it 'runs serially below the threshold' do
    out, = run_rspec('spec/slow_1_spec.rb', env: { 'THRESHOLD' => '50' })

    expect(out).to include('2 examples, 0 failures')
    expect(out).to include('running serially (2 examples is below the threshold of 50)')
    expect(events.grep(/\Aafter_fork/)).to be_empty
  end

  it 'persists example statuses so --only-failures works' do
    status_file = File.join(tmp, 'status.txt')
    run_rspec(env: { 'STATUS_FILE' => status_file })
    out, = run_rspec('--only-failures', env: { 'STATUS_FILE' => status_file, 'THRESHOLD' => '1' })

    expect(out).to include('2 examples, 2 failures')
  end

  it 'reports a crashed worker, keeps going and exits non-zero' do
    out, status = run_rspec(env: { 'CRASH_WORKER' => '1' })

    expect(out).to match(/Worker \d crashed while running .*crash_spec\.rb \(Crashing group\)/)
    expect(out).to include('16 examples, 2 failures, 1 pending, 1 error occurred outside of examples')
    expect(status).not_to eq(0)
  end
end
