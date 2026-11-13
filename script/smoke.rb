# frozen_string_literal: true
# rbs_inline: enabled

require 'bundler'
require 'open3'
require 'rubygems/installer'
require 'tmpdir'
require 'fileutils'

# Installs the built gem plus Thor into an isolated gem home and runs real
# Thor CLI pass, fail and prompt cases there: no Rake, RSpec or OSC
# companion may be present in the runtime gem environment.
class InstalledSmoke
  # @rbs @package: String
  # @rbs @entrypoint: String

  #: (String) -> void
  def initialize(package)
    @package = File.expand_path(package)
  end

  #: () -> void
  def run
    Dir.mktmpdir('thor-osc7501-installed-') do |directory|
      install(Gem.loaded_specs.fetch('thor').cache_file, directory)
      installed = install(@package, directory)
      @entrypoint = File.realpath(File.join(installed.full_gem_path, 'lib/thor/osc7501.rb'))
      check(directory, 'pass', 0)
      check(directory, 'fail', 1)
      check(directory, 'prompt', 0, "y\n")
    end
    puts 'Installed Thor pass/fail/prompt verified without any Rake or RSpec companion'
  end

  private

  #: (String, String) -> Gem::Specification
  def install(package, directory)
    constructor = Gem::Installer.respond_to?(:at) ? :at : :new
    Gem::Installer.public_send(constructor, package, install_dir: directory, ignore_dependencies: true).install
  end

  #: (String, String, Integer, ?String) -> void
  def check(directory, mode, expected_status, stdin = '')
    source = <<~CODE
      # frozen_string_literal: true
      require 'thor/osc7501'
      abort 'Wrong installed entrypoint' unless $LOADED_FEATURES.include?(#{@entrypoint.inspect})
      abort 'Companion loaded' if Gem::Specification.any? { |spec| spec.name.start_with?('rspec', 'rake') }
      class Smoke < Thor
        desc 'pass', 'pass'
        def pass
          puts 'ordinary output'
        end

        desc 'fail', 'fail'
        def fail
          raise 'expected failure'
        end

        desc 'prompt', 'prompt'
        def prompt
          answer = ask('Proceed?')
          puts "answered: \#{answer}"
        end
      end
      Smoke.start(ARGV)
    CODE
    abort 'Rake loaded in installed smoke' if source.include?("require 'rake'")
    # @type var environment: Hash[String, String?]
    environment = { 'GEM_HOME' => directory, 'GEM_PATH' => directory, 'HOME' => directory,
                    'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'SPEC_OPTS' => nil,
                    'THOR_OSC7501' => 'force' }
    clean = Bundler.respond_to?(:with_unbundled_env) ? :with_unbundled_env : :with_clean_env
    output, error, status = Bundler.public_send(clean) do
      Open3.capture3(environment, Gem.ruby, '-e', source, mode, chdir: directory, stdin_data: stdin)
    end
    raise "Wrong process outcome: #{output}\n#{error}" unless status.exitstatus == expected_status

    records = output.scan(/\e\]7501;([^\e]*)\e\\/).map do |(body)|
      body.split(':').map do |field|
        field.split('=', 2)
      end.to_h
    end
    expected_final = mode == 'fail' ? 'error' : 'done'
    raise 'Wrong parent outcome' unless records.last['app'] == 'thor' && records.last['state'] == expected_final
    raise 'Root record carries identity' unless records.all? { |record| !record.key?('id') }
    raise 'Ordinary output missing' unless output.include?('ordinary output') || mode != 'pass'
    return unless mode == 'prompt'

    blocked = records.find { |record| record['state'] == 'blocked' }
    raise 'Missing blocked prompt record' unless blocked && blocked['kind'] == 'question'
  end
end

InstalledSmoke.new(ARGV.fetch(0)).run if $PROGRAM_NAME == __FILE__
