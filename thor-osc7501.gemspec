# frozen_string_literal: true
# rbs_inline: enabled

require_relative 'lib/thor/osc7501/version'

Gem::Specification.new do |spec|
  spec.name = 'thor-osc7501'
  spec.version = Thor::OSC7501::VERSION
  spec.authors = ['Brian Cosgrove']
  spec.email = ['cosgroveb@users.noreply.github.com']
  spec.description = 'Reports Thor command and prompt activity through OSC 7501.'
  spec.summary = 'Opt-in OSC 7501 terminal status for Thor commands'
  spec.homepage = 'https://github.com/cosgroveb/thor-osc7501'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 2.1'
  spec.metadata = {
    'source_code_uri' => 'https://github.com/cosgroveb/thor-osc7501',
    'bug_tracker_uri' => 'https://github.com/cosgroveb/thor-osc7501/issues',
    'changelog_uri' => 'https://github.com/cosgroveb/thor-osc7501/blob/main/CHANGELOG.md'
  }
  spec.files = Dir['lib/**/*.rb'] + Dir['examples/Thorfile'] +
               %w[README.md CHANGELOG.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md ACCESSIBILITY.md]
  spec.require_paths = ['lib']
  spec.add_runtime_dependency 'thor', '>= 0.19.4'
end
