# frozen_string_literal: true
# rbs_inline: enabled

require 'open3'
require 'tmpdir'
require 'rbconfig'
require 'io/console'
require 'English'

# Runs Thor sources in isolated processes with bounded timeouts, reaping
# every child, and returns captured records alongside ordinary output.
class ProcessHelpers
  #: (source: String, argv: Array[String], ?mode: String, ?stdin: String, ?thor_cli: bool) -> Hash[Symbol, untyped]
  def self.run_cli(source:, argv:, mode: 'force', stdin: '', thor_cli: false)
    Dir.mktmpdir('thor osc7501 ') do |directory|
      prepare(directory, source, thor_cli)
      command = thor_command(directory, argv, thor_cli)
      output, error, status = capture({ 'THOR_OSC7501' => mode, 'TERM' => nil }, command, directory, stdin)
      { frames: frames_from(output), titles: titles_from(output), stdout: without_frames(output),
        stderr: error, status: status }
    end
  end

  # PTY-driven run: yields once the given state appears in the output, then
  # sends input or a signal and waits for exit. Bounded waits; children
  # always reaped. SIGINT reproduces Ctrl-C at a blocked prompt as an
  # Interrupt in the reader; the raw byte is not a signal without a
  # controlling-terminal foreground group.
  #: (source: String, argv: Array[String], ?mode: String, ?input: String, ?wait_state: String, ?signal: String, ?thor_cli: bool) -> Hash[Symbol, untyped]
  def self.run_tty(source:, argv:, mode: 'force', input: '', wait_state: nil, signal: nil, thor_cli: false)
    Dir.mktmpdir('thor osc7501 tty ') do |directory|
      prepare(directory, source, thor_cli)
      command = thor_command(directory, argv, thor_cli)
      output, status = capture_tty({ 'THOR_OSC7501' => mode, 'TERM' => 'xterm-256color' }, command, directory,
                                   input, wait_state, signal)
      { frames: frames_from(output), titles: titles_from(output), stdout: without_frames(output),
        pty: output, status: status }
    end
  end

  #: (String, String, bool) -> void
  def self.prepare(directory, source, thor_cli)
    name = thor_cli ? 'Thorfile' : 'cli.rb'
    File.write(File.join(directory, name), source)
  end
  private_class_method :prepare

  #: (String, Array[String], bool) -> Array[String]
  def self.thor_command(directory, argv, thor_cli)
    lib = File.expand_path('../../lib', __dir__)
    if thor_cli
      [RbConfig.ruby, '-I', lib, '-S', 'thor', *argv]
    else
      [RbConfig.ruby, '-I', lib, File.join(directory, 'cli.rb'), *argv]
    end
  end
  private_class_method :thor_command

  #: (Hash[String, String?], Array[String], String, String) -> [String, String, Process::Status]
  def self.capture(environment, command, directory, stdin)
    Open3.popen3(environment, *command, chdir: directory, pgroup: true) do |input, output, error, waiter|
      input.write(stdin) unless stdin.empty?
      input.close
      readers = [output, error].map { |stream| Thread.new { stream.read } }
      begin
        raise 'Thor subprocess timeout' unless waiter.join(30)

        [readers[0].value, readers[1].value, waiter.value]
      ensure
        unless waiter.join(0)
          Process.kill('KILL', -waiter.pid)
          waiter.join
        end
        readers.each(&:join)
      end
    end
  end
  private_class_method :capture

  #: (Hash[String, String?], Array[String], String, String, String?, String?) -> [String, Process::Status]
  def self.capture_tty(environment, command, directory, input, wait_state, signal)
    require 'pty'
    master, slave = PTY.open
    pid = Process.spawn(environment, *command, chdir: directory, in: slave, out: slave, err: slave, pgroup: true)
    slave.close
    output = +''
    status = nil
    sent = input.empty? && signal.nil?
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    begin
      loop do
        if IO.select([master], nil, nil, 0.05)
          output << master.read_nonblock(65_536)
        end
        if !sent && (!wait_state || output.include?("state=#{wait_state}"))
          if signal
            Process.kill(signal, -pid)
          else
            master.write(input)
          end
          sent = true
        end
        raise 'Thor PTY timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        _, reaped = Process.waitpid2(pid, Process::WNOHANG)
        status ||= reaped if reaped
      end
    rescue EOFError, Errno::EIO
      nil
    end
    _, status = Process.waitpid2(pid) unless status
    [output, status]
  ensure
    unless status
      begin
        Process.kill('KILL', -pid)
        Process.waitpid(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
    begin
      master.close
    rescue Errno::EIO
      nil
    end
  end
  private_class_method :capture_tty

  #: (String) -> Array[Hash[String, String]]
  def self.frames_from(output)
    output.scan(/\e\]7501;([^\e]*)\e\\/).map do |(body)|
      body.split(':').map do |field|
        key, value = field.split('=', 2)
        [key, %w[title msg].include?(key) ? value.unpack('m0').first.force_encoding('UTF-8') : value]
      end.to_h
    end
  end
  private_class_method :frames_from

  #: (String) -> String
  def self.without_frames(output)
    output.gsub(/\e\](?:2|7501);[^\e]*\e\\/, '')
  end

  #: (String) -> Array[String]
  def self.titles_from(output)
    output.scan(/\e\]2;([^\e]*)\e\\/).map { |(title)| title.force_encoding('UTF-8') }
  end
  private_class_method :without_frames, :titles_from
end
