# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require_relative '../../support/process_helpers'

RSpec.describe 'Thor OSC7501 prompts' do
  ACTIVATE = "require 'thor/osc7501'".freeze

  #: (String, Array[String], ?String, ?String) -> Hash[Symbol, untyped]
  def run_prompt(body, argv, stdin = '', mode = 'force')
    source = "# frozen_string_literal: true\n#{ACTIVATE}\n" + body
    ProcessHelpers.run_cli(source: source, argv: argv, mode: mode, stdin: stdin)
  end

  ASK_CLI = <<~'CODE'.freeze
    class Interview < Thor
      desc 'question', 'ask a question'
      def question
        answer = ask('Continue?')
        puts "answered: #{answer}"
      end

      desc 'confirm', 'yes or no'
      def confirm
        puts "yes: #{yes?('Proceed?')}"
      end

      desc 'decline', 'no check'
      def decline
        puts "no: #{no?('Proceed?')}"
      end

      desc 'secret', 'hidden input'
      def secret
        password = ask('Password?', echo: false)
        puts 'secret-answer' if password == 'secret-answer'
        puts "length: #{password.length}"
      end

      desc 'limited', 'limited answers'
      def limited
        choice = ask('Color?', limited_to: %w[red blue], default: 'red')
        puts "choice: #{choice}"
      end
    end
    Interview.start(ARGV)
  CODE

  it 'reports blocked while ask waits and working after the answer' do
    enabled = run_prompt(ASK_CLI, ['question'], "sure\n")
    disabled = run_prompt(ASK_CLI, ['question'], "sure\n", 'off')
    expect(enabled[:stdout]).to eq(disabled[:stdout])
    expect(enabled[:status].exitstatus).to eq(disabled[:status].exitstatus)
    expect(enabled[:stdout]).to include('answered: sure')
    blocked = enabled[:frames].find { |frame| frame['state'] == 'blocked' }
    expect(blocked).to include('kind' => 'question', 'msg' => 'Continue?')
    working = enabled[:frames].select { |frame| frame['state'] == 'working' }.map { |frame| frame['msg'] }
    expect(working).to eq(%w[question question])
    expect(enabled[:frames].last['state']).to eq('done')
    expect(enabled[:frames].map { |frame| frame['msg'] }.join).not_to include('sure')
  end

  it 'reports yes? and no? prompts once each without leaking answers' do
    [['confirm', 'y'], ['decline', 'n']].each do |command, _answer|
      enabled = run_prompt(ASK_CLI, [command], "y\n")
      messages = enabled[:frames].map { |frame| frame['msg'] }
      expect(messages).to eq([command, 'Proceed?', command, 'Completed']), command
      expect(enabled[:frames].last['state']).to eq('done')
    end
  end

  it 'never emits hidden input' do
    enabled = run_prompt(ASK_CLI, ['secret'], "secret-answer\n")
    disabled = run_prompt(ASK_CLI, ['secret'], "secret-answer\n", 'off')
    expect(enabled[:stdout]).to eq(disabled[:stdout])
    expect(enabled[:status].exitstatus).to eq(disabled[:status].exitstatus)
    expect(enabled[:frames].map { |frame| frame['msg'] }.join).not_to include('secret-answer')
  end

  it 'stays blocked through limited-answer retries' do
    enabled = run_prompt(ASK_CLI, ['limited'], "green\nred\n")
    expect(enabled[:stdout]).to include('choice: red')
    blocked = enabled[:frames].select { |frame| frame['state'] == 'blocked' }
    expect(blocked.size).to eq(1)
    expect(enabled[:frames].map { |frame| frame['msg'] }.join).not_to include('green')
  end

  it 'delegates EOF behavior to Thor unchanged' do
    enabled = run_prompt(ASK_CLI, ['question'], '')
    disabled = run_prompt(ASK_CLI, ['question'], '', 'off')
    expect(enabled[:stdout]).to eq(disabled[:stdout])
    expect(enabled[:status].exitstatus).to eq(disabled[:status].exitstatus)
  end

  it 'does not double-report when a prompt occurs without a run' do
    source = <<~CODE
      # frozen_string_literal: true
      #{ACTIVATE}
      shell = Thor::Shell::Basic.new
      puts "direct: \#{shell.ask('Standalone?')}"
    CODE
    enabled = ProcessHelpers.run_cli(source: source, argv: [], mode: 'force', stdin: "x\n")
    expect(enabled[:frames]).to eq([])
    expect(enabled[:stdout]).to include('direct: x')
  end

  describe 'on the real CLI shell' do
    THORFILE = <<~'CODE'.freeze
      require 'thor/osc7501'
      class Interview < Thor
        desc 'question', 'ask a question'
        def question
          puts "answered: #{ask('Continue?')}"
        end

        desc 'color', 'color shell'
        def color
          shell = Thor::Shell::Color.new
          puts "color answered: #{shell.ask('Continue?')}"
        end

        desc 'explicit', 'explicit shell'
        def explicit
          shell = Thor::Shell::Basic.new
          puts "explicit answered: #{shell.ask('Continue?')}"
        end

        desc 'identity', 'shell identity'
        def identity
          say "shell: #{shell.class}"
          puts "asked: #{ask('Continue?')}"
        end
      end
    CODE

    it 'reports prompts on the shell created before Thorfile loading' do
      enabled = ProcessHelpers.run_cli(source: THORFILE, argv: ['interview:question'], mode: 'force',
                                        stdin: "go\n", thor_cli: true)
      disabled = ProcessHelpers.run_cli(source: THORFILE, argv: ['interview:question'], mode: 'off',
                                        stdin: "go\n", thor_cli: true)
      expect(enabled[:stdout]).to eq(disabled[:stdout])
      expect(enabled[:frames].select { |frame| frame['state'] == 'blocked' }
                 .map { |frame| frame['msg'] }).to eq(['Continue?'])
      expect(enabled[:frames].last['state']).to eq('done')
    end

    it 'reports prompts on Color and explicitly supplied standard shells' do
      %w[interview:color interview:explicit].each do |command|
        enabled = ProcessHelpers.run_cli(source: THORFILE, argv: [command], mode: 'force',
                                          stdin: "go\n", thor_cli: true)
        expect(enabled[:frames].select { |frame| frame['state'] == 'blocked' }
                   .map { |frame| frame['msg'] }).to eq(['Continue?']), command
        expect(enabled[:frames].last['state']).to eq('done')
      end
    end

    it 'preserves the configured shell identity and options' do
      enabled = ProcessHelpers.run_cli(source: THORFILE, argv: ['interview:identity'], mode: 'force',
                                        stdin: "go\n", thor_cli: true)
      expect(enabled[:stdout]).to include('shell: Thor::Shell::Color')
      expect(enabled[:frames].last['state']).to eq('done')
    end
  end

  describe 'PTY attention behavior' do
    WORK_CLI = <<~'CODE'.freeze
      class Deploy < Thor
        desc 'confirm', 'confirm before finishing'
        def confirm
          say 'about to finish'
          answer = ask('Proceed?')
          say "proceeding: #{answer}"
        end

        desc 'fail', 'raise after answering the prompt'
        def fail
          ask('Proceed?')
          raise 'boom'
        end
      end
      Deploy.start(ARGV)
    CODE

    it 'blocks before input and resumes after it on a TTY' do
      enabled = ProcessHelpers.run_tty(source: "#{ACTIVATE}\n#{WORK_CLI}", argv: ['confirm'],
                                        input: "y\n", wait_state: 'blocked')
      expect(enabled[:frames].map { |frame| frame['state'] }).to include('blocked', 'working', 'done')
      expect(enabled[:frames].last['state']).to eq('done')
      expect(enabled[:stdout]).to include('proceeding: y')
    end

    it 'reports idle after Ctrl-C at a blocked prompt with no records after the final' do
      enabled = ProcessHelpers.run_tty(source: "#{ACTIVATE}\n#{WORK_CLI}", argv: ['confirm'],
                                        wait_state: 'blocked', signal: 'INT')
      expect(enabled[:frames].last['state']).to eq('idle')
      finals = enabled[:frames].rindex { |frame| %w[done error idle].include?(frame['state']) }
      expect(enabled[:frames][(finals + 1)..]).to eq([])
      expect(enabled[:status].signaled?).to eq(true)
      expect(enabled[:status].termsig).to eq(Signal.list['INT'])
    end

    it 'does not overwrite the final error when cleanup follows a failure' do
      enabled = ProcessHelpers.run_tty(source: "#{ACTIVATE}\n#{WORK_CLI}", argv: ['fail'],
                                        input: "y\n", wait_state: 'blocked')
      expect(enabled[:frames].last['state']).to eq('error')
      finals = enabled[:frames].rindex { |frame| %w[done error idle].include?(frame['state']) }
      expect(enabled[:frames][(finals + 1)..]).to eq([])
    end  end
end
