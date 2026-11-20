# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require 'thor/osc7501/run'

RSpec.describe Thor::OSC7501::Run do
  let(:output) { StringIO.new }

  #: (String, String) -> Thor::OSC7501::Run
  def make_run(mode = 'force')
    described_class.new(output, mode: mode)
  end

  #: () -> Array[String]
  def working_messages
    frames(output.string).select { |frame| frame['state'] == 'working' }.map { |frame| frame['msg'] }
  end

  #: () -> Array[String]
  def final_states
    frames(output.string).select { |frame| %w[done error idle].include?(frame['state']) }
        .map { |frame| frame['state'] }
  end

  it 'reports nested commands with caller restoration' do
    run = make_run
    value = run.during_run do
      run.during_command('outer') { run.during_command('inner') { :value } }
    end
    expect(value).to eq(:value)
    expect(working_messages).to eq(['outer', 'inner', 'outer'])
    expect(final_states).to eq(['done'])
  end

  it 'emits no working record when the active stack empties' do
    run = make_run
    run.during_run { run.during_command('solo') { :value } }
    expect(working_messages).to eq(['solo'])
    expect(final_states).to eq(['done'])
  end

  it 'counts concurrent command contexts and names the survivor' do
    run = make_run
    ready = Queue.new
    release = Queue.new
    results = run.during_run do
      workers = Array.new(2) do |index|
        Thread.new do
          run.during_command("worker#{index}") do
            ready << true
            release.pop
            "result#{index}"
          end
        end
      end
      2.times { ready.pop }
      expect(working_messages).to include('2 active commands')
      2.times { release << true }
      workers.map(&:value)
    end
    expect(results).to eq(%w[result0 result1])
    messages = working_messages
    expect(messages).to include('worker0', 'worker1', '2 active commands')
    expect(%w[worker0 worker1]).to include(messages.last)
    expect(final_states).to eq(['done'])
  end

  it 'returns the outer run result unchanged' do
    run = make_run
    result = run.during_run { run.during_command('outer') { run.during_command('inner') { 42 } } }
    expect(result).to eq(42)
  end

  it 'reports error for an escaping exception and re-raises unchanged' do
    run = make_run
    expect do
      run.during_run { run.during_command('boom') { raise 'kaput' } }
    end.to raise_error('kaput')
    expect(final_states).to eq(['error'])
  end

  it 'reports idle for Interrupt and re-raises unchanged' do
    run = make_run
    expect do
      run.during_run { run.during_command('work') { raise Interrupt } }
    end.to raise_error(Interrupt)
    expect(final_states).to eq(['idle'])
  end

  it 'reports idle for a successful SystemExit and re-raises it' do
    run = make_run
    expect do
      run.during_run { run.during_command('work') { exit(0) } }
    end.to raise_error(SystemExit) { |exception| expect(exception.success?).to eq(true) }
    expect(final_states).to eq(['idle'])
  end

  it 'reports error for an unsuccessful SystemExit and re-raises it' do
    run = make_run
    expect do
      run.during_run { run.during_command('work') { exit(1) } }
    end.to raise_error(SystemExit) { |exception| expect(exception.success?).to eq(false) }
    expect(final_states).to eq(['error'])
  end

  it 'does not finalize the run when an inner exception is handled' do
    run = make_run
    run.during_run do
      run.during_command('outer') do
        run.during_command('inner') { raise 'inner failure' }
      rescue StandardError
        nil
      end
    end
    expect(final_states).to eq(['done'])
    expect(working_messages).to eq(%w[outer inner outer])
  end

  it 'does not overwrite the final record with late cleanup' do
    run = make_run
    late = Thread.new do
      run.during_run do
        run.during_command('late') { run.during_command('child') { :value } }
      end
    end
    late.join
    expect(final_states).to eq(['done'])
    late_cleanup = Array.new(2) { |index| Thread.new { run.during_command("cleanup#{index}") { :value } } }
    late_cleanup.each(&:join)
    expect(final_states).to eq(['done'])
  end

  it 'is synchronized: concurrent commands never interleave a corrupted record' do
    run = make_run
    run.during_run do
      threads = Array.new(8) do |index|
        Thread.new { run.during_command("cmd#{index}") { index } }
      end
      threads.map(&:value)
    end
    records = frames(output.string)
    expect(records).to(all(have_keys('app', 'state', 'msg')))
    expect(final_states).to eq(['done'])
  end

  it 'gives pending prompts priority over working commands and restores after' do
    run = make_run
    in_prompt = Queue.new
    release = Queue.new
    worker = Thread.new do
      run.during_run do
        run.during_command('worker') do
          run.during_prompt('Continue?') do
            in_prompt << true
            release.pop
            'answered'
          end
        end
      end
    end
    in_prompt.pop
    expect(frames(output.string).last).to include('state' => 'blocked', 'kind' => 'question', 'msg' => 'Continue?')
    release << true
    answer = worker.value
    expect(answer).to eq('answered')
    expect(working_messages.last).to eq('worker')
    expect(final_states).to eq(['done'])
  end

  it 'restores the most recent still-pending prompt when an earlier one resolves' do
    run = make_run
    first_entered = Queue.new
    second_entered = Queue.new
    release_first = Queue.new
    release_second = Queue.new
    earlier = Thread.new do
      run.during_prompt('first?') do
        first_entered << true
        release_first.pop
      end
    end
    first_entered.pop
    later = Thread.new do
      run.during_prompt('second?') do
        second_entered << true
        release_second.pop
      end
    end
    second_entered.pop
    expect(frames(output.string).last['msg']).to eq('second?')
    release_second << true
    later.join
    expect(frames(output.string).last['msg']).to eq('first?')
    release_first << true
    earlier.join
    expect(final_states).to eq([])
  end

  #: (*String) -> Object
  def have_keys(*keys)
    satisfy { |frame| keys.all? { |key| frame.key?(key) } }
  end
end
