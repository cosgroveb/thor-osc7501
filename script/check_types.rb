# frozen_string_literal: true
# rbs_inline: enabled

require 'ripper'
require 'rbs'
require 'fileutils'

# Every authored file opts into inline RBS and every method carries a `#:`
# annotation. Unlike the sibling Rake adapter, `untyped` is permitted at the
# Thor framework boundary: command objects, shell arguments and Thor's own
# dispatch values are dynamically typed APIs, and pretending precision there
# would be false precision.
files = Dir['{lib,spec,script}/**/*.rb'] + Dir['Gemfile*'].reject do |f|
  f.end_with?('.lock')
end + %w[Rakefile Steepfile thor-osc7501.gemspec]
methods = 0
files.each do |path|
  source = File.read(path)
  abort "Missing inline RBS opt-in: #{path}" unless source.include?('# rbs_inline: enabled')
  lines = source.lines
  Ripper.lex(source).each do |position, event, token, _state|
    next unless event == :on_kw && token == 'def'

    index = position.first - 2
    comments = [] #: Array[String]
    while index >= 0 && lines[index].lstrip.start_with?('#')
      comments.unshift(lines[index])
      index -= 1
    end
    signature = comments.join[/^\s*#:\s*(.+)$/, 1]
    abort "Missing method annotation: #{path}:#{position.first}" unless signature
    RBS::Parser.parse_method_type(signature)
    methods += 1
  end
end

FileUtils.rm_rf('tmp/signatures')
files.each_with_index do |path, index|
  # Separate outputs avoid Gemfile/Gemfile.compat basename collisions.
  success = system('rbs-inline', '--base=.', "--output=tmp/signatures/#{index}", path)
  abort "Signature generation failed: #{path}" unless success
end
abort 'Implementation type checking failed' unless system('steep', 'check', '-j', '2')
puts "Validated inline RBS: #{files.size} files, #{methods} methods. Checked runtime and tooling implementations"
