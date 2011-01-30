#require 'lib/mediawiki.rb'
#LOG_DIR_PATH = File.dirname(__FILE__) + '/../log'

require 'mediawiki.rb'
require 'logger'
require 'sqlite3'
require 'rubygems'
require 'bundler/setup'

# require gems
require 'eventmachine'
require 'sinatra/base'
require 'em-http'
require 'nokogiri'
require 'sequel'

##########
# event machine based mediawiki irc scraper with external link following
# based on https://github.com/purzelrakete/mini/
#
#########

#TODO pull this stuff out of the mini module, put it in event machine?
#TODO extract the irc specific stuff into a gem
#TOOD add commands to kill the sqlite file/generically clear the db and logs (before start: something like: -c)
module Mini
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
        EventMachine::run do
          Mini::IRC.connect(options)
          @signature = EventMachine::start_server("0.0.0.0", options[:mini_port].to_i, Mini::Listener)
          Bot.secret = options[:secret]
          EventMachine.threadpool_size = 50
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
      proc ? proc.call(args) : (@@irc_log.error "command #{ command } not found. ")
    end
    
    def self.stop
      @@log.info('stopping')
      server_resp = EventMachine.stop_server(@signature)
      #anything? sleep? or loop?
      em_resp = EventMachine.stop
      @@log.info("server said: #{server_resp} and eventmachine said: #{em_resp}")
    end
  end
end

module Mini
  class IRC < EventMachine::Connection
    include EventMachine::Protocols::LineText2
    #include Mediawiki
    attr_accessor :config, :moderators
    #cattr_accessor :connection
    
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
    
    def self.connect(options)
      self.connection = EM.connect(options[:server], options[:port].to_i, self, options)
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
      when /^PING (.*)/ : command('PONG', $1)
      when /^:(.*?)\ :Nickname\ is\ already\ in\ use\.$/ :  #:[hostname] 433 * [username] :Nickname is already in use.
        raise RuntimeError.new('nickname in use') #TODO make our own exception for this
      #TODO do some further checking on whether we're successful in connection to channel/etc.: http://www.networksorcery.com/enp/protocol/irc.htm
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
        	  sample_table = DB[:samples]
        	  sample_table << fields
        	  if should_follow?(fields[:title])
        	    sleep(5) #wait for mediawiki propogation...
        	    follow_revision(fields)
        	    #@@irc_log.info("would have follow this revision")
      	    end
      	  end
  	    rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@irc_log.error "Followed irc, resulting in: #{e}"
	      end
      end
      #@@irc_log.info "here"
      # Callback block to execute once the request is fulfilled
      #callback = proc do |res|
      #	resp.send_response
      #end

      # Let the thread pool (20 Ruby threads) handle request
      EM.defer(process_line)#, callback)
    end
    
    def follow_revision fields
      #get the xml from wikipedia
      url = Mediawiki::form_url({:prop => :revisions, :revids => fields[:revision_id], :rvdiffto => 'prev', :rvprop => 'ids|flags|timestamp|user|size|comment|parsedcomment|tags|flagged' })
      #TODO wikipeida requires a User-Agent header, and we didn't supply one, so em-http must...
      EventMachine::HttpRequest.new(url).get.callback do |http|
        #@@irc_log.info('hit mediawiki servers')
        done = false
        begin
          #parse the xml
          xml = http.response.to_s
          noked = Nokogiri.XML(xml)
          #@@irc_log.info('nok\'ed the xml')
          #test to see if we have a badrevid
          if noked.css('badrevids').first == nil
            diff, attrs, tags = Mediawiki::parse_revision(xml) #don't really like doing this transformation twice...

            #parse it for links
            links = Mediawiki::parse_links(diff)
            #if there are links, investigate!
            unless links.empty?
              #pulling the source via EM shouldn't block...
              links.each do |url_and_desc|
                url = url_and_desc.first
                url_regex = /^(.*?\/\/)([^\/]*)(.*)$/x
                #deal with links stargin with 'www', if they get entered into wikilinks like that they count!
                unless url =~ url_regex
                  url = "http://#{url}"
                end
                revision_id = fields[:revision_id]
                description = url_and_desc.last
                follow_link(revision_id, url, description)
                @@irc_log.info("would have followed link: #{url}")
              end # end links each
            else
              @@irc_log.info("no links")
            end #end unless (following link)
          else
            @@irc_log.error "badrevids: #{noked.css('badrevids').to_s}"
          end #end bad revid check
          done = true
        rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@irc_log.error "problem following revision: #{e}"
          @@irc_log.error e.backtrace.join("\n") if e.backtrace
        ensure
          @@irc_log.error("broken at following revisions") unless done
        end #end rescue
      
      end #end em-http
    end #end follow-revisions
    
    
    def follow_link revision_id, url, description
      EventMachine::HttpRequest.new(url).get(:redirects => 10).callback do |http|
        begin
          #revision_id = fields[:revision_id]
          #description = url_and_desc.last
          #shallow copy all reponse headers to a hash with lowercase symbols as keys
          #em-http converts dashs to symbols
          headers = http.response_header.inject({}){|memo,(k,v)| memo[k.to_s.downcase.to_sym] = v; memo}
          #@@irc_log.info("followed link: #{url}; #{headers[:content_type]}")
          #ignore binary, non content-type text/html files
          unless(headers[:content_type] =~ /^text\/html/ )
            @@irc_log.info("stored source: #{url}")
            fields = {
              :source => http.response.to_s[0..10**3].gsub(/\x00/, ''), #
              :headers => Marshal.dump(headers), 
              :url => url, 
              :revision_id => revision_id, 
              :wikilink_description => description
            }

            link_table = DB[:links]
        	  link_table << fields
      	  else
            fields = {
              :source => 'encoded', 
              :headers => Marshal.dump(headers), 
              :url => url, 
              :revision_id => revision_id, 
              :wikilink_description => description
            }

            link_table = DB[:links]
        	  link_table << fields
    	    end
        rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@irc_log.error "Followed link: #{e}"
        end #end rescue
      end #end em-http
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
      EM.add_timer(3) do
        @@irc_log.info 'unbind'
        reconnect(config[:server], config[:port].to_i)
        post_init
      end
    end
  end
end

module Mini
  module Listener
    def receive_data(data) # echo "#musicteam,#legal,@alice New album uploaded: ..." | nc somemachine 12345.
      all, targets, *payload = *data.match(/^(([\#@]\S+,? ?)*)(.*)$/)
      targets = targets.split(",").map { |target| target.strip }.uniq
      IRC.connection.say(payload.pop.strip, targets)
    end
  end
end

log = Logger.new("#{LOG_DIR_PATH}/db.log")
log.level = Logger::WARN
DB = Sequel.sqlite "en_wikipedia.sqlite", :logger => log
#DB.sql_log_level = :debug
unless DB.table_exists?(:samples)
  DB.create_table :samples do
    primary_key :id #autoincrementing primary key
    String :title
    String :flags
    String :user
    Integer :old_id
    Integer :revision_id
    Integer :byte_diff
    String :comment
    #DateTime :created, :default => :'(datetime(\'now\'))'.sql_function() #TODO
  end
end
unless DB.table_exists?(:links)
  DB.create_table :links do
    primary_key :id #autoincrementing primary key
    String :source, :text => true #or blob?
    String :headers, :text => true
    String :url
    Integer :revision_id
    String :wikilink_description
    #DateTime :created, :default => :'(datetime(\'now\'))'.sql_function() #TODO
  end
end

Mini::Bot.start(
  :secret => 'GHMFQPKNANMNTHQDECECSCWUCMSNSHSAFRGFTHHD',
  :mini_port => 12345,
  :web_port => 2345,
  :server => 'irc.wikimedia.org',#server,
  :port => '6667',#port,
  :user => 'yasb',#user,
  :password => '',#password, 
  :channels => ['en.wikipedia']#[*channels]
)
# :default => :'datetime(\'now\',\'localtime\')'.sql_function
# DATE DEFAULT (datetime('now','localtime'))s