require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'
require 'sinatra/base'
require 'em-http'
require 'sequel'
require 'sqlite3'
require 'god/cli/run'

require 'lib/em_xlink.rb'
require 'lib/em_irc.rb'

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
          DateTime :created, :default => "(datetime('now'))".lit
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
          DateTime :created, :default => "(datetime('now'))".lit
        end
      end
      
      #get insert statements ready: http://sequel.rubyforge.org/rdoc/files/doc/prepared_statements_rdoc.html
      #DB[:items].prepare(:insert, :insert_with_name, :name=>:$n)
      #DB.call(:insert_with_name, :n=>'Jim')
      #DB[:items].prepare(:insert, :insert_with_name, :name=>:$n)
      #DB.call(:insert_with_name, :n=>'Jim')
    end
    
    def start_irc
      EmMwXlink::Bot.start(
        :secret => 'GHMFQPKNANMNTHQDECECSCWUCMSNSHSAFRGFTHHD',
        :mini_port => 12345,
        :web_port => 2345,
        :server => 'irc.wikimedia.org',#server,
        :port => '6667',#port,
        :user => 'yasb',#user,
        :password => '',#password, 
        :channels => ['en.wikipedia']#[*channels]
      )
    end
    
    def start_xlink_1
      EventMachine.run do
        @sig = EventMachine.start_server('127.0.0.1', 7890, EmMwXlink::RevisionReceiver)
      end
    end
    
    def start_xlink_2
      EventMachine.run do
        @sig = EventMachine.start_server('127.0.0.1', 8901, EmMwXlink::RevisionReceiver)
      end
    end
    
    def start_god
      #auto bind to port
      options = { :daemonize => true, :pid => 'tmp/god.pid', :log => 'log/god.log', :port => "0", :syslog => false, :events => false, :config => 'xlink.god', :log_level => :info  } #:attach => , #TODO attach to the main pid
      God::CLI::Run.new(options)
    end
  end
end