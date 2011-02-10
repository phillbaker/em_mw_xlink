require 'irc.rb'
require 'xlink_client.rb'

module EmMwXlink
  class Bot
    @@commands = {}
    
    def self.commands= commands
      @@commands = commands
    end
    def self.commands
      @@commands
    end
    def self.secret= secret
      @@secret = secret
    end
    def self.secret
      @@secret
    end
    def self.start(options)
      begin
        @@log = Logger.new("#{LOG_DIR_PATH}/bot.log")
        @@log.info('starting')
        EventMachine.run do
          EventMachine.threadpool_size = 50
          Bot.secret = options[:secret]
          #@@secret = options[:secret]
          
          #connect to our unstable revision processors
          conn = EventMachine.connect('127.0.0.1', XLINK_PORT_PRIMARY, EmMwXlink::XlinkClient, {:port => XLINK_PORT_PRIMARY})
          options[:xlink_1] = conn #pass it to the IRC listener so we can check the status before passing off revisions
          @@log.info(conn.to_s)
          conn = EventMachine.connect('127.0.0.1', XLINK_PORT_SECONDARY, EmMwXlink::XlinkClient, {:port => XLINK_PORT_SECONDARY})
          options[:xlink_2] = conn
          @@log.info(conn.to_s)
          
          #connect to the IRC channel
          conn = EventMachine.connect(options[:server], options[:port].to_i, EmMwXlink::IRC, options)
          EmMwXlink::IRC.connection = conn #store it there...
        end
      rescue Exception => e
        if e.is_a?(RuntimeError) && (e.to_s == 'no acceptor' || e.to_s == 'nickname in use')
          @@log.error(e.to_s)
          #this should be if we're trying to use a port that's already been taken 
          raise e  #TODO throw a more specific exception (create our own?) like PortInUse
        else
          begin
            @@log.error('Running bot')
            @@log.error(e)
            @@log.error(e.backtrace)
          rescue Exception => e #in case we can't even make the log
            puts e
          end
        end
      end
    end
    
    def self.run(command, args)
      proc = Bot.commands[command]
      proc ? proc.call(args) : (@@log.error "command #{ command } not found. ")
    end
    
    def self.stop
      @@log.info('stopping')
      
      #log out of the irc
      conn = EmMwXlink::IRC.connection
      @@log.info('Quitting from IRC channel')
      conn.command('QUIT')#log out of the irc channel
      #drop the connection so that we can reconnect if necessary
      conn.close_connection()

      #stop eventmachine
      EventMachine.stop_event_loop
      
      EM.next_tick do
        @@log.info("there are #{EM.connection_count.to_s} connections left")
      end
      sleep(1)
      EventMachine.stop
      #should I just call: 
      #Doesn't really matter, it's called in the launch script exit(1) #should really kill this process
    end
  end
end