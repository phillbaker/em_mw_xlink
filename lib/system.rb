require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'
require 'sinatra/base'
require 'em-http'
require 'sequel'
require 'sqlite3'

require 'lib/em_xlink.rb'
require 'lib/em_irc.rb'

module EmMwXlink
  class<<self
    DB = nil #holder for db connection
    
    def start_db
      log = Logger.new("#{LOG_DIR_PATH}/db.log")
      log.level = Logger::WARN
      DB = Sequel.sqlite "en_wikipedia.sqlite", :logger => log
      #DB.sql_log_level = :debug
      # :default => :'datetime(\'now\',\'localtime\')'.sql_function
      # DATE DEFAULT (datetime('now','localtime'))s
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
  end
end