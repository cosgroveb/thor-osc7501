# frozen_string_literal: true
# rbs_inline: enabled

require 'thor'
require_relative 'run'

class Thor
  module OSC7501
    # Prepended to Thor::Command: wraps executed commands in Run
    # contexts. Hooking Command#run sits after Thor's invocation
    # deduplication, so skipped commands produce no records. Late
    # prepending the Base module alone would not reach existing
    # includers (verified on Ruby 2.1 during research). The module's
    # self type is declared in sig/dependencies.rbs: rbs-inline cannot
    # emit it.
    module CommandHook
      #: [T] (untyped instance, *untyped args) { (*untyped) -> T } -> T
      def run(instance, *args, &block)
        return super if OSC7501.framework_command?(self)
        run = OSC7501.current_run
        if run
          run.during_command(name) { super }
        else
          OSC7501.start_run { |outer| outer.during_command(name) { super } }
        end
      end
    end

    # Prepended to Thor::Base-derived classes' singleton classes: owns the
    # single root record for the outer run. Nested .start calls and nested
    # dispatches reuse the active run.
    module StartHook
      #: [T] (*untyped args) { (*untyped) -> T } -> T
      def start(*args, &block)
        return super if OSC7501.current_run
        OSC7501.start_run { super(*args, &block) }
      end
    end

    # Prepended to Thor::Shell::Basic: reports pending prompts on the
    # configured shell without replacing it. Covers Basic and subclasses
    # such as Color, including shells created before activation. Shells
    # overriding ask directly are outside guaranteed coverage.
    module ShellHook
      #: [T] (untyped statement, *untyped args) { (*untyped) -> T } -> T
      def ask(statement, *args, &block)
        run = OSC7501.current_run
        if run
          run.during_prompt(statement.to_s) { super(statement, *args, &block) }
        else
          super
        end
      end
    end

    # Prepended to Thor::Base's singleton class: hooks classes that
    # include Thor::Base after activation.
    module IncludeHook
      #: (Class base) -> void
      def included(base)
        super
        return unless base.is_a?(Class)
        return if base.singleton_class.ancestors.include?(StartHook)
        base.singleton_class.prepend(StartHook)
      end
    end

    # Framework-owned commands never count as application work.
    FRAMEWORK_COMMANDS = %w[help list version install installed update uninstall tree].freeze

    class << self
      # @rbs @installed: bool
      # @rbs @run: Run?

      #: () -> void
      def install!
        return if @installed
        @installed = true
        Thor::Command.prepend(CommandHook)
        Thor::Base.subclasses.each do |klass|
          next if klass.singleton_class.ancestors.include?(StartHook)
          klass.singleton_class.prepend(StartHook)
        end
        Thor::Base.singleton_class.prepend(IncludeHook)
        Thor::Shell::Basic.prepend(ShellHook)
      end

      #: () -> Run?
      def current_run
        @run
      end

      #: [T] () { (Run) -> T } -> T
      def start_run
        run = Run.new($stdout, mode: ENV.fetch('THOR_OSC7501', 'auto'))
        previous = @run
        @run = run
        begin
          run.during_run { yield run }
        ensure
          @run = previous
        end
      end

      # Framework identity is the command object registered by the Thor
      # framework classes themselves, not the command name: user commands
      # called list or version keep reporting.
      #: (untyped command) -> bool
      def framework_command?(command)
        return false unless FRAMEWORK_COMMANDS.include?(command.name)
        return true if command.equal?(Thor.all_commands[command.name])
        return false unless defined?(Thor::Runner)
        command.equal?(Thor::Runner.all_commands[command.name])
      end
    end
  end
end
