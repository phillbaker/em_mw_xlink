require 'mediawiki.rb'

require 'logger'
# require bundled gems
require 'eventmachine'

##########
# event machine based mediawiki irc scraper with external link following
# based on https://github.com/purzelrakete/mini/
#
#########

#TODO extract the irc specific stuff into a gem
module EmMwXlink
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
        	      #@@irc_log.info('sending to numero uno')
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

      # Let the thread pool (Ruby threads) handle request
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
end
