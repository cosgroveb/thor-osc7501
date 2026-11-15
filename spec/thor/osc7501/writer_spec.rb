# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require 'thor/osc7501/writer'

# Minimal IO stand-ins; avoid mock plumbing around the writer contract.
class TtyOutput < StringIO
  #: () -> bool
  def tty?
    true
  end
end

class BrokenOutput
  #: (String) -> Integer
  def write(_text)
    raise Errno::EPIPE
  end

  #: () -> nil
  def flush
    nil
  end

  #: () -> bool
  def tty?
    false
  end
end

class ExplodingTty
  #: () -> bool
  def tty?
    raise IOError
  end
end

RSpec.describe Thor::OSC7501::Writer do
  let(:output) { StringIO.new }

  #: (StringIO, String) -> Thor::OSC7501::Writer
  def writer(io, mode = 'force')
    described_class.new(io, mode: mode)
  end

  it 'emits decodable frames with protocol fields' do
    result = writer(output).emit(state: 'blocked', msg: "Proceed?\n", kind: 'question')
    expect(result).to be_nil
    expect(frames(output.string).last).to include('app' => 'thor', 'state' => 'blocked',
                                                  'kind' => 'question', 'msg' => 'Proceed?')
    expect(frames(output.string).last).not_to have_key('id')
    expect(frames(output.string).last).not_to have_key('progress')
  end

  it 'emits exact ST-wrapped bytes with title Thor' do
    writer(output).emit(state: 'working', msg: 'deploy')
    body = output.string[/\e\]7501;([^\e]*)\e\\/, 1]
    expect(body).to eq("app=thor:title=VGhvcg==:state=working:msg=#{['deploy'].pack('m0')}")
    expect(output.string).to start_with("\e]2;thor\e\\\e]7501;").and(end_with("\e\\"))
    expect(output.string).to eq(output.string.delete("\n"))
  end

  it 'composes a bounded sanitized window title with the prefix' do
    writer(output).emit(state: 'working', msg: 'deploy',
                        window_title: "\e\xFF\n".b.force_encoding('UTF-8') + "\a install " * 300)
    title = output.string[/\A\e\]2;([^\e]*)\e\\/, 1]
    expect(title.bytesize).to be <= 512
    expect(title).to be_valid_encoding
    expect(title).to start_with('thor › ')
  end

  it 'falls back to the bare prefix without a window title' do
    writer(output).emit(state: 'done', msg: 'Completed')
    expect(output.string).to start_with("\e]2;thor\e\\")
  end

  it 'omits the kind field when no kind is given' do
    writer(output).emit(state: 'working', msg: 'deploy')
    expect(frames(output.string).last).not_to have_key('kind')
  end

  it 'bounds messages to 2048 UTF-8 bytes without splitting characters' do
    text = 'é' * 3000
    writer(output).emit(state: 'working', msg: text)
    emitted = frames(output.string).last['msg']
    expect(emitted).to be_valid_encoding
    expect(emitted.bytesize).to be <= 2048
    expect(emitted).to eq('é' * 1024)
  end

  it 'replaces invalid bytes with valid replacement text' do
    binary = "broken-\xE2\x28\xA1".dup.force_encoding('BINARY')
    writer(output).emit(state: 'working', msg: binary)
    expect(frames(output.string).last['msg']).to be_valid_encoding
  end

  it 'removes terminal formatting before leftover control characters' do
    writer(output).emit(state: 'working', msg: "\e[31mDeploy\e[0m finished\t\x01done")
    expect(frames(output.string).last['msg']).to eq('Deploy finished done')
  end

  it 'normalizes whitespace to a single line' do
    writer(output).emit(state: 'blocked', msg: "Continue?\n  extra   lines\n")
    expect(frames(output.string).last['msg']).to eq('Continue? extra lines')
  end

  it 'writes one record per emit separated by nothing extra' do
    writer(output).emit(state: 'working', msg: 'one')
    writer(output).emit(state: 'done', msg: 'Completed')
    expect(frames(output.string).map { |frame| frame['state'] }).to eq(%w[working done])
  end

  describe 'modes' do
    it 'emits in force mode without a TTY' do
      expect { writer(output, 'force').emit(state: 'working', msg: 'x') }.to change { output.string }
    end

    it 'stays silent in off mode' do
      expect { writer(output, 'off').emit(state: 'working', msg: 'x') }.not_to(change { output.string })
    end

    it 'stays silent in auto mode without a TTY' do
      expect { writer(output, 'auto').emit(state: 'working', msg: 'x') }.not_to(change { output.string })
    end

    it 'stays silent in auto mode with a dumb terminal' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TERM').and_return('dumb')
      tty = TtyOutput.new
      expect { writer(tty, 'auto').emit(state: 'working', msg: 'x') }.not_to(change { tty.string })
    end

    it 'emits in auto mode on a TTY with a usable TERM' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('TERM').and_return('xterm-256color')
      tty = TtyOutput.new
      writer(tty, 'auto').emit(state: 'working', msg: 'x')
      expect(frames(tty.string).last['state']).to eq('working')
    end

    it 'rejects invalid modes' do
      expect { writer(output, 'loud') }.to raise_error(ArgumentError, /THOR_OSC7501 must be auto, off, or force/)
    end
  end

  describe 'reporting IO failures' do
    it 'disables reporting on write failure' do
      broken = BrokenOutput.new
      instance = writer(broken)
      expect { instance.emit(state: 'working', msg: 'x') }.not_to raise_error
      expect { instance.emit(state: 'done', msg: 'Completed') }.not_to raise_error
    end

    it 'disables reporting when TTY detection fails' do
      instance = described_class.new(ExplodingTty.new, mode: 'auto')
      expect { instance.emit(state: 'working', msg: 'x') }.not_to raise_error
    end

    it 'does not replace a caller exception raised around emit' do
      allow(output).to receive(:write).and_raise(IOError)
      instance = writer(output)
      expect do
        begin
          instance.emit(state: 'working', msg: 'x')
          raise 'caller failure'
        end
      end.to raise_error('caller failure')
    end
  end
end
