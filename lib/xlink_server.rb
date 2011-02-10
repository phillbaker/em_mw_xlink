require 'xlink.rb'

module EmMwXlink
  #this is the unstable version and we're going to monitor whether they're available on different ports
  module RevisionServer
    include EventMachine::Protocols::ObjectProtocol
    
    def receive_object(revision_hash)
      EmMwXlink::follow_revision(revision_hash)
    end
    
  end
  
end