# frozen_string_literal: true
# rbs_inline: enabled

require_relative 'osc7501/version'
require_relative 'osc7501/hooks'

# Requiring this entrypoint activates Thor OSC 7501 reporting once:
# ordinary Thor commands and prompts emit terminal status while output,
# input, return values and exit behavior stay unchanged.
class Thor
  module OSC7501
    install!
  end
end
