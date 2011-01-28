require 'mediawiki.rb'

require 'logger'
require 'rubygems'
require 'sqlite3'
require 'bundler/setup'

# require gems
require 'eventmachine'
require 'sinatra/base'
require 'em-http'
require 'nokogiri'
require 'sequel'


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
        EventMachine::run do
          Mini::IRC.connect(options)
          EventMachine::start_server("0.0.0.0", options[:mini_port].to_i, Mini::Listener)
          Bot.secret = options[:secret]
          #@@web.run! :port => options[:web_port].to_i #TODO this hijacks external output
        end
      rescue Exception => e
        puts e
        puts e.backtrace
      end
    end
    
    def self.run(command, args)
      proc = Bot.commands[command]
      proc ? proc.call(args) : (puts "command #{ command } not found. ")
    end
    
    #TODO self.stop? EventMachine::stop_event_loop. 
  end
end

module Mini
  class IRC < EventMachine::Connection
    include EventMachine::Protocols::LineText2
    include Mediawiki
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
        #self.config = OpenStruct.new(options)
        self.config = options
        @queue = []
      rescue Exception => e
        puts e
        puts e.backtrace
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
    end
    
    def receive_line(line)
      case line
      when /^PING (.*)/ : command('PONG', $1)
      when /^:(\S+) PRIVMSG (.*) :\?(.*)$/ : queue($1, $2, $3)
      when /^:\S* \d* #{ config[:user] } @ #{ '#' + config[:channels].first } :(.*)/ : dequeue($1)
      else #TODO when do we end up here? #this is all received lines?
        #STDOUT.print(line + "\n")
        #STDOUT.flush()
        handle_line(line)
      end 
    end
    
    def handle_line line
      process_line = proc do
      	if line =~ Mediawiki::IRC_REGEXP
      	  fields = process_irc(line)
      	  samples = DB[:samples]
      	  samples << fields
      	  if should_follow?(fields[:title])
      	    puts 'following'
      	    follow_revision(fields)
    	    end
    	  end
      end

      # Callback block to execute once the request is fulfilled
      #callback = proc do |res|
      #	resp.send_response
      #end

      # Let the thread pool (20 Ruby threads) handle request
      EM.defer(process_line)#, callback)
    end
    
    def follow_revision fields
      #get the diff and associated data
      data = get_diff_data(fields[:revision_id])
      
      #parse it for links
      #if there are links, investigate!
      #EM.defer()
    end
    
    def get_diff_data revision_id
      #get the xml from wikipedia
      url = form_url({:prop => :revisions, :revids => rev_id, :rvdiffto => 'prev', :rvprop => 'ids|flags|timestamp|user|size|comment|parsedcomment|tags|flagged' })
      EM::HttpRequest.new(url).get.callback do |http|
        puts http.response.to_s[0..100]
      end
      
      #parse the xml
      #test to see if we have a badrevid
      #pull out the diff_xml (TODO and other stuff)
      
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
        puts 'unbind'
        reconnect(config[:server], config[:port])
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

DB = Sequel.sqlite "en_wikipedia.sqlite", :logger => Logger.new('log/db.log')
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
    String :source
    String :headers
    String :url
    Integer :revision_id
    String :wikilink_description
    #DateTime :created, :default => :'(datetime(\'now\'))'.sql_function() #TODO
  end
end

# @samples = DB[:samples]
# @samples << {
#   :comment=>"Robot: Listifying from Category:Candidates for speedy deletion (51 entries)", 
#   :title=>"User:Cyde/List of candidates for speedy deletion/Subpage", 
#   :flags=>"MB", 
#   :revision_id=>410531074, 
#   :old_id=>410530660, 
#   :byte_diff=>130, :user=>"Cydebot"}
# puts @samples.count

Mini::Bot.start(
  :secret => 'GHMFQPKNANMNTHQDECECSCWUCMSNSHSAFRGFTHHD',
  :mini_port => 12345,
  :web_port => 2345,
  :server => 'irc.wikimedia.org',#server,
  :port => '6667',#port,
  :user => 'ayasb',#user,
  :password => '',#password, 
  :channels => ['en.wikipedia']#[*channels]
)

#DB = Sequel.connect('sqlite://blog.db', :logger => Logger.new('log/db.log'))

# :default => :'datetime(\'now\',\'localtime\')'.sql_function
# DATE DEFAULT (datetime('now','localtime'))