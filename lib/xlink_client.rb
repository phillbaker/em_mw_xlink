module EmMwXlink
  #call with EM.connect
  class XlinkClient < EventMachine::Connection
    include EventMachine::Protocols::ObjectProtocol
    attr_accessor :config
    
    def initialize options
      self.config = options
    end
    
    def send_revision revision
      send_object(revision)
    end
    
    #when we loose a connection, pause for 30s and then try to reconnect, give it time to be rebooted
    def unbind
      EM.add_timer(10) do
        reconnect('127.0.0.1', config[:port])
      end
    end
  end
end