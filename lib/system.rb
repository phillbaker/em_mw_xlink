require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'
require 'em-http'
require 'sequel'
require 'sqlite3'
require 'god/cli/run'

require 'lib/xlink_server.rb'
require 'lib/bot.rb'
require 'lib/web.rb'

module EmMwXlink
  class<<self
    def db
      @@db
    end
    
    def start_db
      log = Logger.new("#{LOG_DIR_PATH}/db.log")
      log.level = Logger::WARN
      @@db = Sequel.sqlite "en_wikipedia.sqlite", :logger => log
      #DB.sql_log_level = :debug
      # :default => :'datetime(\'now\',\'localtime\')'.sql_function
      # DATE DEFAULT (datetime('now','localtime'))s
      unless @@db.table_exists?(:samples)
        @@db.create_table :samples do
          primary_key :id #autoincrementing primary key
          String :title
          String :flags
          String :user
          Integer :old_id
          Integer :revision_id
          Integer :byte_diff
          String :comment
          DateTime :created, :default => "(datetime('now'))".lit #"YYYY-MM-DD HH:MM:SS" in GMT
        end
      end
      unless @@db.table_exists?(:links)
        @@db.create_table :links do
          primary_key :id #autoincrementing primary key
          Blob :source
          Blob :headers
          String :url
          Integer :revision_id
          String :wikilink_description
          Integer :status
          String :last_effective_url
          DateTime :created, :default => "(datetime('now'))".lit
        end
      end
      
      #get insert statements ready: http://sequel.rubyforge.org/rdoc/files/doc/prepared_statements_rdoc.html
      @@db[:samples].prepare(:insert, :insert_sample, 
        :title => :$title, 
        :flags => :$flags, 
        :user => :$user, 
        :old_id => :$old_id, 
        :revision_id => :$revision_id, 
        :byte_diff => :$byte_diff, 
        :comment => :$comment
      )
      @@db[:links].prepare(:insert, :insert_link,
        :source => :$source,
        :headers => :$headers,
        :url => :$url,
        :revision_id => :$revision_id,
        :wikilink_description => :$wikilink_description,
        :status => :$status,
        :last_effective_url => :$last_effective_url
      )
    end
    
    #blocks
    def start_irc
      EmMwXlink::Bot.start(
        :server => 'irc.wikimedia.org',#server,
        :port => '6667',#port,
        :user => IRC_USER,#user,
        :password => '',#password, 
        :channels => ['en.wikipedia']#[*channels]
      )
    end
    
    #blocks
    def start_web
      EmMwXlinkStats.secret = 'GHMFQPKNANMNTHQDECECSCWUCMSNSHSAFRGFTHHD'
      handler = Rack::Handler.get('mongrel')
      #basically taken from the run! method in sinatra
      handler_name = handler.name.gsub(/.*::/, '')
      handler.run EmMwXlinkStats, :Host => '0.0.0.0', :Port => WEB_PORT do |server|
        [:INT, :TERM].each { |sig| trap(sig) { server.respond_to?(:stop!) ? server.stop! : server.stop } }
        EmMwXlinkStats.set :running, true
      end
    end
    
    #blocks
    def start_xlink_1
      EventMachine.run do
        @sig = EventMachine.start_server('0.0.0.0', XLINK_PORT_PRIMARY, EmMwXlink::RevisionServer)
      end
    end
    
    #blocks
    def start_xlink_2
      EventMachine.run do
        @sig = EventMachine.start_server('0.0.0.0', XLINK_PORT_SECONDARY, EmMwXlink::RevisionServer)
      end
    end
    
    def start_god
      #auto bind to port
      #TODO move all of these to File.join(LOG_DIR + ...)
      options = { :daemonize => true, :pid => 'tmp/god.pid', :port => GOD_PORT.to_s, :syslog => false, :events => false, :config => 'xlink.god', :log => 'log/god.log', :log_level => :info } #:attach => , #TODO attach to the main pid
      God::CLI::Run.new(options)
    end
  end
end