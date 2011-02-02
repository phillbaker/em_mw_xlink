require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'
require 'sinatra/base'
require 'em-http'
require 'sequel'
require 'sqlite3'

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
# :default => :'datetime(\'now\',\'localtime\')'.sql_function
# DATE DEFAULT (datetime('now','localtime'))s