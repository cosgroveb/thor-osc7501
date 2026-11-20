# frozen_string_literal: true
# rbs_inline: enabled

require 'spec_helper'
require 'rubygems'
require 'rubygems/package'

# rubocop:disable RSpec/DescribeClass -- package contract does not map to one class
RSpec.describe 'Packaged artifact', :aggregate_failures do
  let(:spec) { Gem::Specification.load('thor-osc7501.gemspec') }

  it 'declares the compatibility floor and the single runtime dependency' do
    expect(spec.required_ruby_version).to eq(Gem::Requirement.new('>= 2.1'))
    expect(spec.runtime_dependencies.map(&:name)).to eq(['thor'])
    expect(spec.runtime_dependencies.first.requirement).to eq(Gem::Requirement.new('>= 0.19.4'))
  end

  it 'packages generated consumer signatures into the built gem' do
    package = "pkg/#{spec.full_name}.gem"
    skip 'package not built' unless File.file?(package)

    files = Gem::Package.new(File.open(package, 'rb')).tap(&:verify).spec.files
    expect(files.grep(%r{\Asig/.*\.rbs\z})).not_to be_empty
    expect(files).to include('lib/thor/osc7501.rb')
  end

  it 'keeps generated signatures out of the source tree' do
    expect(Dir['sig/**/*.rbs']).to all(satisfy { |path| path == 'sig/dependencies.rbs' })
  end
end
# rubocop:enable RSpec/DescribeClass
