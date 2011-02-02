require 'rubygems'
require 'bundler/setup'
require 'eventmachine'

require 'lib/em_xlink.rb'

class EmXlink2
  class<<self
    def start
      EventMachine.run do
        EventMachine.start_server('127.0.0.1', 8901, EmMwXlink::RevisionReceiver)
      end
    end
  end
end
