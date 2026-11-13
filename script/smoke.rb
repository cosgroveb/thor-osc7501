# frozen_string_literal: true
# rbs_inline: enabled

require 'bundler'
require 'open3'
require 'rubygems/installer'
require 'tmpdir'

# Run packaged code with an isolated gem home and no checkout load paths.
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
      check(directory, 'pass', 0, '')
      check(directory, 'fail', 1, '')
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

  #: (String, String, Integer, String) -> void
  def check(directory, mode, expected_status, stdin)
    # Plain string building, no squiggly heredoc: this smoke also runs on Ruby 2.1.
    source = "require 'thor/osc7501'\n"
    source += "abort 'Wrong installed entrypoint' unless $LOADED_FEATURES.include?(#{@entrypoint.inspect})\n"
    source += "abort 'Companion loaded' if Gem.loaded_specs.keys.any? { |name| name.start_with?('rspec', 'rake') }\n"
    source += "class Smoke < Thor\n"
    source += "  desc 'pass', 'pass'\n"
    source += "  def pass\n"
    source += "    puts 'ordinary output'\n"
    source += "  end\n"
    source += "\n"
    source += "  desc 'fail', 'fail'\n"
    source += "  def fail\n"
    source += "    raise 'expected failure'\n"
    source += "  end\n"
    source += "\n"
    source += "  desc 'prompt', 'prompt'\n"
    source += "  def prompt\n"
    source += "    answer = ask('Proceed?')\n"
    source += '    puts "answered: #{answer}"' + "\n"
    source += "  end\n"
    source += "end\n"
    source += 'Smoke.start(ARGV)'
    File.write(File.join(directory, 'cli.rb'), source)
    # @type var environment: Hash[String, String?]
    environment = { 'GEM_HOME' => directory, 'GEM_PATH' => directory, 'HOME' => directory,
                    'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'SPEC_OPTS' => nil,
                    'THOR_OSC7501' => 'force' }
    clean = Bundler.respond_to?(:with_unbundled_env) ? :with_unbundled_env : :with_clean_env
    output, error, status = Bundler.public_send(clean) do
      Open3.capture3(environment, Gem.ruby, File.join(directory, 'cli.rb'), mode, chdir: directory, stdin_data: stdin)
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
    raise 'Ordinary output missing' if mode == 'pass' && !output.include?('ordinary output')
    return unless mode == 'prompt'

    blocked = records.find { |record| record['state'] == 'blocked' }
    raise 'Missing blocked prompt record' unless blocked && blocked['kind'] == 'question'
  end
end

InstalledSmoke.new(ARGV.fetch(0)).run if $PROGRAM_NAME == __FILE__
