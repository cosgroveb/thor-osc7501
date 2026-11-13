# frozen_string_literal: true
# rbs_inline: enabled

require 'stringio'
require 'thor/osc7501'

module FrameHelpers
  #: (String) -> Array[Hash[String, String]]
  def frames(output)
    output.scan(/\e\]7501;([^\e]*)\e\\/).map do |(body)|
      body.split(':').map do |field|
        key, value = field.split('=', 2)
        [key, %w[title msg].include?(key) ? value.unpack('m0').first.force_encoding('UTF-8') : value]
      end.to_h
    end
  end

  #: (String) -> String
  def without_frames(output)
    output.gsub(/\e\]7501;[^\e]*\e\\/, '')
  end
end

RSpec.configure do |config|
  config.include FrameHelpers
  config.order = :random
  Kernel.srand config.seed
end
