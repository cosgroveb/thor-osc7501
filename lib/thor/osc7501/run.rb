# frozen_string_literal: true
# rbs_inline: enabled

require_relative 'writer'

class Thor
  module OSC7501
    # Owns the single root record for one outer Thor run: active command
    # contexts, pending prompts and the final outcome. Private to the
    # adapter. Hooks call during_run/during_command/during_prompt.
    class Run # :nodoc: all
      # @rbs @writer: Writer
      # @rbs @mutex: Mutex
      # @rbs @finished: bool
      # @rbs @reported_work: bool
      # @rbs @erred: bool
      # @rbs @stacks: Hash[Thread, Array[String]]
      # @rbs @prompts: Array[[Thread, String]]

      #: (IO | StringIO output, mode: String) -> void
      def initialize(output, mode:)
        @writer = Writer.new(output, mode: mode)
        @mutex = Mutex.new
        @finished = false
        @reported_work = false
        @erred = false
        @stacks = {}
        @prompts = []
      end

      # A run finalizes only if real work or a prompt was reported:
      # framework-only invocations (help, list, version) produce no
      # records at all. An exception escaping the outermost command
      # marks the run failed even when Thor consumes it at the outer
      # boundary (exit_on_failure? false). Errors handled inside an
      # enclosing command body do not.
      #: [T] () { () -> T } -> T
      def during_run
        result = yield
        finish(@erred ? 'error' : 'done', @erred ? 'Failed' : 'Completed')
        result
      rescue Exception => e # Preserve Thor's handling of Interrupt and SystemExit.
        stopped = e.is_a?(Interrupt) || (e.is_a?(SystemExit) && e.success?)
        finish(stopped ? 'idle' : 'error', stopped ? 'Stopped' : 'Failed')
        raise
      end

      #: [T] (String) { () -> T } -> T
      def during_command(name)
        stack = (@stacks[Thread.current] ||= [])
        @mutex.synchronize do
          @reported_work = true
          stack << name
          report
        end
        begin
          yield
        rescue Exception
          # Sole-command escape reaches Thor's outer boundary: mark the
          # run failed even if Thor consumes the error there.
          @mutex.synchronize { @erred = true if sole_context?(stack) }
          raise
        ensure
          @mutex.synchronize do
            stack.pop
            @stacks.delete(Thread.current) if stack.empty?
            report
          end
        end
      end

      #: [T] (String) { () -> T } -> T
      def during_prompt(text)
        # @type var prompt: [Thread, String]
        prompt = [Thread.current, text]
        @mutex.synchronize do
          @reported_work = true
          @prompts << prompt
          report
        end
        begin
          yield
        ensure
          @mutex.synchronize do
            @prompts.delete(prompt)
            report
          end
        end
      end

      private

      #: (String, String) -> void
      def finish(state, message)
        @mutex.synchronize do
          return unless @reported_work
          @finished = true
          @writer.emit(state: state, msg: message)
        end
      end

      # Pending prompts take priority over working commands. No default
      # working record is emitted when no command remains active: the
      # run's finalization provides the next record.
      #: () -> void
      def report
        return if @finished

        prompt = @prompts.last
        if prompt
          @writer.emit(state: 'blocked', msg: prompt[1], kind: 'question')
          return
        end
        active = active_commands
        return if active.empty?
        if active.size == 1
          @writer.emit(state: 'working', msg: active.first.last)
        else
          @writer.emit(state: 'working', msg: "#{active.size} active commands")
        end
      end

      #: () -> Array[Array[String]]
      def active_commands
        @stacks.values.reject(&:empty?)
      end

      #: (Array[String]) -> bool
      def sole_context?(stack)
        @stacks.values.all? { |other| other.equal?(stack) || other.empty? } && stack.length == 1
      end
    end
  end
end
