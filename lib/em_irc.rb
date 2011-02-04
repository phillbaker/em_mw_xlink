#require 'lib/mediawiki.rb'
#LOG_DIR_PATH = File.dirname(__FILE__) + '/../log'

require 'mediawiki.rb'

require 'logger'
require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'
require 'sinatra/base'
require 'sequel'
require 'sqlite3'

##########
# event machine based mediawiki irc scraper with external link following
# based on https://github.com/purzelrakete/mini/
#
#########

#TODO pull this stuff out of the mini module, put it in event machine?
#TODO extract the irc specific stuff into a gem
#TOOD add commands to kill the sqlite file/generically clear the db and logs (before start: something like: -c)
module EmMwXlink
  class Bot
    #cattr_accessor :commands, :secret
    @@commands = {}
    @@web = Sinatra.new do
      #post("/:command/:secret") do
        #command, secret = params.delete("command"), params.delete("secret")
        #Mini::IRC.connection.execute([command, params].join(" ")) if secret == Mini::Bot.secret
      get '/' do
        Mini::Bot.secret
      end
    end
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
          
          #connect to our unstable revision processors
          conn = EventMachine.connect('127.0.0.1', 7890, EmMwXlink::RevisionSender, {:port => 7890})
          options[:xlink_1] = conn
          @@log.info(conn.to_s)
          conn = EventMachine.connect('127.0.0.1', 8901, EmMwXlink::RevisionSender, {:port => 8901})
          options[:xlink_2] = conn
          @@log.info(conn.to_s)
          
          #connect to the IRC channel
          conn = EventMachine.connect(options[:server], options[:port].to_i, EmMwXlink::IRC, options)
          EmMwXlink::IRC.connection = conn #store it there...
          
          #start our server to say things back
          #@signature = EventMachine::start_server("0.0.0.0", options[:mini_port].to_i, EmMwXlink::IrcListener)
          #Bot.secret = options[:secret]
          #@@web.run! :port => options[:web_port].to_i #TODO this hijacks external output
          
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
      #EventMachine.stop_server(@signature)
      
      EM.next_tick do
        @@log.info("there are #{EM.connection_count.to_s} connections left")
      end
      sleep(1)
      EventMachine.stop
      #should I just call: 
      #Doesn't really matter, it's called in the launch script exit(1) #should really kill this process
    end
  end

  class IRC < EventMachine::Connection
    include EventMachine::Protocols::LineText2
    attr_accessor :config, :moderators
    
    def self.connection= connection
      @@connection = connection
    end
    
    def self.connection
      @@connection
    end
    
    def initialize(options)
      begin
        self.config = options
        @queue = []
        @@irc_log = Logger.new("#{LOG_DIR_PATH}/irc.log")
      rescue Exception => e
        puts e
      end
    end
        
    def say(msg, targets = [])
      targets = ['#' + config[:channels].first] if targets.blank?
      msg.split("\n").each do |msg| 
        targets.each do |target| 
          command( (msg.starts_with?("/") ? msg[1..-1] : "PRIVMSG #{ target.delete("@") } :#{ msg }") )
        end
      end
    end
    
    def command(*cmd)
      send_data "#{ cmd.flatten.join(' ') }\r\n"
    end
        
    def queue(sender, receiver, msg)
      @queue << [sender.split("!").first, msg]
      command "NAMES", "#" + config[:channels].first
    end

    def dequeue(nicks)
      self.moderators = nicks.split.map { |nick| nick.delete("@").delete("+") }
      
      while job = @queue.pop
        sender, cmd = job
        execute(cmd) if self.moderators.include?(sender)
      end
    end
    
    def execute(cmd)
      command = "minicmd #{ [*cmd].join(' ') }"
      say(%x{#{ command }})
    end
    
    # callbacks
    def post_init
      command "USER", [config[:user]]*4
      command "NICK", config[:user]
      command("NickServ IDENTIFY", config[:user], config[:password]) if config[:password]
      config[:channels].each { |channel| command("JOIN", "##{ channel }")  } if config[:channels]
      #TODO if we get the name already used error, raise a runtime exception or something to go all the way back to start.rb
    end
    
    def receive_line(line)
      case line
      #/^PING :(.*)$/
      when /^PING :(.*)$/ : 
        command('PONG', $1)
        @@irc_log.info(line)
      when /^:(.*?)\ :Nickname\ is\ already\ in\ use\.$/ :  
        #:[hostname] 433 * [username] :Nickname is already in use.
        raise RuntimeError.new('nickname in use') #TODO make our own exception for this
      #TODO do some further checking on whether we're successful in connection to channel/etc.: 
      # http://www.networksorcery.com/enp/protocol/irc.htm
      when /^:(\S+) PRIVMSG (.*) :\?(.*)$/ : queue($1, $2, $3)
      when /^:\S* \d* #{ config[:user] } @ #{ '#' + config[:channels].first } :(.*)/ : dequeue($1)
      else
        handle_line(line)
      end 
    end
    
    def handle_line line
      process_line = proc do
        begin
        	if line =~ Mediawiki::IRC_REGEXP
        	  fields = process_irc(line)
        	  sample_table = EmMwXlink::db[:samples]
        	  sample_table << fields #something else to do is to create a new column that tracks whether we've successfully tracked this guy
        	  if should_follow?(fields[:title])
        	    sleep(5) #wait for mediawiki propogation...
        	    #push to other, out of process EM clients to deal with; let them die/etc
        	    unless(self.config[:xlink_1].error?) 
        	      @@irc_log.info('sending to numero uno')
        	      self.config[:xlink_1].send_revision(fields)
      	      else
      	        #TODO need to deal with reconnecting to the restarted 1
      	        @@irc_log.info('failing over to numero dos')
      	        self.config[:xlink_2].send_revision(fields)
    	        end
      	    end
    	    else
    	      @@irc_log.info(line)
      	  end
  	    rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@irc_log.error "Followed irc, resulting in: #{e}"
	      end
      end
      # Callback block to execute once the request is fulfilled
      #callback = proc do |res|
      #	resp.send_response
      #end

      # Let the thread pool (20 Ruby threads) handle request
      EM.defer(process_line)#, callback)
    end

    
    #given the irc announcement in the irc monitoring channel for en.wikipedia, this returns the different fields
    # 0: title (string), 
    # 1: flags (desc) (string), 
    # 2: revision_id (rev_id) (integer),
    # 3: old_id (integer)
    # 4: user (string), 
    # 5: byte_diff (integer), 
    # 6: comment (description) (string)
    def process_irc message
      fields = message.scan(Mediawiki::IRC_REGEXP).first
      #get rid of the diff/oldid and oldid/rcid groups
      fields.delete_at(4)
      fields.delete_at(2)
      fields[2] = fields[2].to_i
      fields[3] = fields[3].to_i
      fields[5] = fields[5].to_i
      {:title => fields[0], :flags => fields[1], :revision_id => fields[2], :old_id => fields[3], :user => fields[4], :byte_diff => fields[5], :comment => fields[6]}
    end
    
    #look at title, exclude titles starting with: User talk, Talk, Wikipedia, User, etc.
    def should_follow? article_title 
      bad_beg_regex = /^(Talk:|User:|User\stalk:|Wikipedia:|Wikipedia\stalk:|File\stalk:|MediaWiki:|MediaWiki\stalk:|Template\stalk:|Help:|Help\stalk:|Category\stalk:|Thread:|Thread\stalk:|Summary\stalk:|Portal\stalk:|Book\stalk:|Special:|Media:)/
      !(article_title =~ bad_beg_regex)
    end
    
    def unbind
      #@@irc_log.info('Quitting from IRC channel')
      #command "QUIT" #log out of the irc channel
      #don't think I want this reconnection right here...
      # EM.add_timer(3) do
      #   @@irc_log.info 'unbind'
      #   reconnect(config[:server], config[:port].to_i)
      #   post_init
      # end
    end
  end

  module IrcListener #actually, 
    def receive_data(data) # echo "#musicteam,#legal,@alice New album uploaded: ..." | nc somemachine 12345.
      all, targets, *payload = *data.match(/^(([\#@]\S+,? ?)*)(.*)$/)
      targets = targets.split(",").map { |target| target.strip }.uniq
      IRC.connection.say(payload.pop.strip, targets)
    end
  end
  
  #call with EM.connect
  class RevisionSender < EventMachine::Connection
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
