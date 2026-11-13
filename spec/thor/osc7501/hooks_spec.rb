# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require 'thor/osc7501/hooks'

RSpec.describe Thor::OSC7501 do
  let(:output) { StringIO.new }

  it 'installs exactly once' do
    described_class.install!
    expect(Thor::Command.ancestors.map(&:to_s).count('Thor::OSC7501::CommandHook')).to eq(1)
    expect(Thor::Base.subclasses).to all(satisfy { |klass| klass.singleton_class.ancestors.include?(Thor::OSC7501::StartHook) })
    described_class.install!
    expect(Thor::Command.ancestors.map(&:to_s).count('Thor::OSC7501::CommandHook')).to eq(1)
    expect(Thor::Shell::Basic.ancestors.map(&:to_s).count('Thor::OSC7501::ShellHook')).to eq(1)
  end

  it 'observes classes defined after activation through the include hook' do
    described_class.install!
    klass = Class.new { include Thor::Base }
    expect(klass.singleton_class.ancestors).to include(Thor::OSC7501::StartHook)
  end

  describe '.framework_command?' do
    it 'suppresses framework commands by registered command identity' do
      require 'thor/runner'
      %w[help list version install update uninstall].each do |name|
        command = Thor::Runner.all_commands[name]
        expect(described_class.framework_command?(command)).to eq(true), name
      end
      expect(described_class.framework_command?(Thor.all_commands['help'])).to eq(true)
    end

    it 'reports user commands named list or version' do
      user = Class.new(Thor) do
        desc 'list', 'user list'
        #: () -> nil
        def list; end

        desc 'version', 'user version'
        #: () -> nil
        def version; end
      end
      expect(described_class.framework_command?(user.all_commands['list'])).to eq(false)
      expect(described_class.framework_command?(user.all_commands['version'])).to eq(false)
    end
  end
end
