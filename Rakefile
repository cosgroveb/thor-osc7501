# frozen_string_literal: true
# rbs_inline: enabled

require 'rubygems/package_task'
require 'fileutils'
require 'rspec/core/rake_task'
require_relative 'lib/thor/osc7501'

RSpec::Core::RakeTask.new(:spec)
specification = Gem::Specification.load('thor-osc7501.gemspec')
Gem::PackageTask.new(specification) do |task|
  task.package_dir = 'pkg'
end

task :package_signatures do
  directory = "pkg/#{specification.full_name}"
  FileUtils.rm_rf("#{directory}/sig")
  sh 'rbs-inline', '--base=lib', "--output=#{directory}/sig", 'lib'
  specification.files += Dir["#{directory}/sig/**/*.rbs"].map { |path| path.sub("#{directory}/", '') }
end
Rake::Task["pkg/#{specification.full_name}.gem"].enhance([:package_signatures])

desc 'Check runtime and tooling implementations against inline RBS'
task :types do
  ruby 'script/check_types.rb'
end

desc 'Run passing, failing and prompt cases against the installed gem'
task smoke: :package do
  ruby 'script/smoke.rb', "pkg/#{specification.full_name}.gem"
end

task default: %i[types spec smoke]
