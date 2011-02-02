require 'rubygems'
require 'bundler/setup'
require 'eventmachine'

require 'lib/em_xlink.rb'

class EmXlink1
  class<<self
    def start
      EventMachine.run do
        @sig = EventMachine.start_server('127.0.0.1', 7890, EmMwXlink::RevisionReceiver)
      end
    end
  end
end
