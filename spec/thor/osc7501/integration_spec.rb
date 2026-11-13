# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require_relative '../../support/process_helpers'

RSpec.describe 'Thor OSC7501 integration' do
  ACTIVATE = "require 'thor/osc7501'".freeze

  #: (String, ?activate_first: bool) -> String
  def cli_source(body, activate_first: true)
    activation = ACTIVATE
    body = "# frozen_string_literal: true\n" + body
    activate_first ? "#{activation}\n#{body}" : "#{body}\n#{activation}\n"
  end

  #: (String) -> String
  def normalize_paths(text)
    text.gsub(%r{/tmp/[^/\s]+/}, '<tmp>/')
  end

  #: (source: String, argv: Array[String], ?thor_cli: bool, ?stdin: String) -> Array[Hash[Symbol, untyped]]
  def compare(source:, argv:, thor_cli: false, stdin: '')
    enabled = ProcessHelpers.run_cli(source: source, argv: argv, mode: 'force', stdin: stdin,
                                     thor_cli: thor_cli)
    disabled = ProcessHelpers.run_cli(source: source, argv: argv, mode: 'off', stdin: stdin,
                                      thor_cli: thor_cli)
    expect(normalize_paths(enabled[:stdout])).to eq(normalize_paths(disabled[:stdout])), normalize_paths(enabled[:stdout])
    expect(normalize_paths(enabled[:stderr])).to eq(normalize_paths(disabled[:stderr])), normalize_paths(enabled[:stderr])
    expect(enabled[:status].exitstatus).to eq(disabled[:status].exitstatus)
    expect(enabled[:status].termsig).to eq(disabled[:status].termsig)
    [enabled, disabled]
  end

  BASE_COMMANDS = <<~CODE.freeze
    class Deploy < Thor
      desc 'work', 'do work'
      def work
        puts 'working'
      end

      desc 'health', 'health check'
      def health
        puts 'healthy'
      end
    end
  CODE

  it 'reports a direct .start run and preserves ordinary output' do
    enabled, = compare(source: cli_source("#{BASE_COMMANDS}\nDeploy.start(ARGV)"), argv: ['work'])
    expect(enabled[:frames].map { |frame| frame['state'] }).to eq(%w[working done])
    expect(enabled[:frames].first).to include('app' => 'thor', 'msg' => 'work')
    expect(enabled[:frames].last).to include('msg' => 'Completed')
    expect(enabled[:stdout]).to eq("working\n")
  end

  it 'activates when required after class definition' do
    source = <<~CODE
      # frozen_string_literal: true
      require 'thor'
      #{BASE_COMMANDS}
      #{ACTIVATE}
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['work'])
    expect(enabled[:frames].last['state']).to eq('done')
  end

  it 'stays idempotent under duplicate activation' do
    source = cli_source("#{ACTIVATE}\n#{ACTIVATE}\nThor::OSC7501.install!\n#{BASE_COMMANDS}\nDeploy.start(ARGV)")
    enabled, = compare(source: source, argv: ['work'])
    expect(enabled[:frames].count { |frame| frame['state'] == 'working' }).to eq(1)
    expect(enabled[:frames].last['state']).to eq('done')
  end

  it 'reports nested invoke with caller restoration and skips already-run commands' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'outer', 'outer'
        def outer
          puts 'outer start'
          invoke :inner
          invoke :inner
          puts 'outer end'
        end

        desc 'inner', 'inner'
        def inner
          puts 'inner'
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['outer'])
    messages = enabled[:frames].select { |frame| frame['state'] == 'working' }.map { |frame| frame['msg'] }
    expect(messages).to eq(%w[outer inner outer])
    expect(enabled[:stdout]).to eq("outer start\ninner\nouter end\n")
    expect(enabled[:frames].count { |frame| frame['state'] == 'done' }).to eq(1)
  end

  it 'keeps the run open when an inner exception is handled' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'outer', 'outer'
        def outer
          begin
            invoke :boom
          rescue StandardError
            puts 'recovered'
          end
          puts 'outer end'
        end

        desc 'boom', 'boom'
        def boom
          raise 'kaput'
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['outer'])
    expect(enabled[:frames].map { |frame| frame['state'] }.last).to eq('done')
  end

  it 'reports error and preserves exit for an unhandled exception' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'boom', 'boom'
        def boom
          raise 'kaput'
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, disabled = compare(source: source, argv: ['boom'])
    expect(enabled[:frames].last['state']).to eq('error')
    expect(enabled[:status].exitstatus).to eq(1)
  end

  [true, false].each do |exit_on_failure|
    it "reports error for Thor::Error with exit_on_failure? #{exit_on_failure}" do
      source = cli_source(<<~CODE)
        class Deploy < Thor
          def self.exit_on_failure?
            #{exit_on_failure}
          end

          desc 'bad', 'bad'
          def bad
            raise Thor::Error, 'thor failure'
          end
        end
        Deploy.start(ARGV)
      CODE
      enabled, = compare(source: source, argv: ['bad'])
      expect(enabled[:frames].last['state']).to eq('error')
      expect(enabled[:status].exitstatus).to eq(exit_on_failure ? 1 : 0)
    end
  end

  it 'reports idle for exit(0) and error for exit(1), preserving exits' do
    [0, 1].each do |code|
      source = cli_source(<<~CODE)
        class Deploy < Thor
          desc 'quit', 'quit'
          def quit
            exit(#{code})
          end
        end
        Deploy.start(ARGV)
      CODE
      enabled, = compare(source: source, argv: ['quit'])
      expect(enabled[:frames].last['state']).to eq(code.zero? ? 'idle' : 'error')
      expect(enabled[:status].exitstatus).to eq(code)
    end
  end

  it 'reports done for an ordinary false return' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'quiet', 'quiet'
        def quiet
          false
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['quiet'])
    expect(enabled[:frames].last['state']).to eq('done')
  end

  it 'reports idle for Interrupt and preserves termination' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'halt', 'halt'
        def halt
          raise Interrupt
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['halt'])
    expect(enabled[:frames].last['state']).to eq('idle')
    expect(enabled[:status].signaled?).to eq(true)
    expect(enabled[:status].termsig).to eq(Signal.list['INT'])
  end

  it 'keeps working during a synchronous subprocess without a companion' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'build', 'build'
        def build
          output = `#{RbConfig.ruby} -e 'puts "subprocess"'`
          puts output
          puts Object.const_defined?(:RSpec) ? 'RSPEC LOADED' : 'no companion'
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['build'])
    expect(enabled[:stdout]).to include('no companion')
    expect(enabled[:frames].last['state']).to eq('done')
    expect(enabled[:frames].map { |frame| frame['app'] }).to all(eq('thor'))
  end

  it 'reports normal CLI commands loaded from a Thorfile' do
    source = cli_source(<<~CODE, activate_first: true)
      class Deploy < Thor
        default_task :work

        desc 'work', 'do work'
        def work
          puts 'working'
        end
      end
    CODE
    enabled, = compare(source: source, argv: ['deploy'], thor_cli: true)
    expect(enabled[:frames].map { |frame| frame['state'] }).to eq(%w[working done])
    expect(enabled[:frames].first['msg']).to eq('work')
    expect(enabled[:stdout]).to eq("working\n")
  end

  it 'suppresses framework list, version and help operations' do
    %w[list version help].each do |framework_command|
      enabled, = compare(source: cli_source(''), argv: [framework_command], thor_cli: true)
      expect(enabled[:frames]).to eq([]), framework_command
    end
  end

  it 'reports user commands named list and version' do
    source = cli_source(<<~CODE)
      class Deploy < Thor
        desc 'list', 'user list'
        def list
          puts 'user list'
        end

        desc 'version', 'user version'
        def version
          puts 'user version'
        end
      end
      Deploy.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: ['list'])
    expect(enabled[:frames].map { |frame| frame['state'] }).to eq(%w[working done])
    expect(enabled[:frames].first['msg']).to eq('list')
  end

  it 'keeps one run across a Thor::Group sequence' do
    source = cli_source(<<~CODE)
      class Sequence < Thor::Group
        def one
          puts 'one'
        end

        def two
          puts 'two'
        end
      end
      Sequence.start(ARGV)
    CODE
    enabled, = compare(source: source, argv: [])
    states = enabled[:frames].map { |frame| frame['state'] }
    expect(states.count('done')).to eq(1)
    expect(states).to eq(%w[working working done])
    expect(enabled[:frames].map { |frame| frame['msg'] }).to eq(%w[one two Completed])
  end

end
