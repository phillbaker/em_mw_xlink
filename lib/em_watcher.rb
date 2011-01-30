require 'logger'
require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'

class EmWatcher
  def self.start
    Watcher.time = Time.now.to_i #should initialize to starting time
    Watcher.log = Logger.new("#{LOG_DIR_PATH}/watcher.log")
    EM.kqueue = true if EM.kqueue?
    EventMachine.run do
      EventMachine.watch_file("#{LOG_DIR_PATH}/../en_wikipedia.sqlite", Watcher) #TODO don't hardwire this
    end
  end

  module Watcher
    def self.time= time
      @@time = time
    end
    def self.time
      @@time
    end
    def self.log= log
      @@log = log
    end
    def self.log
      @@log
    end
    
    def file_modified
      #puts "#{path} modified"
      #Watcher.log().info('db file modified')
      last = Watcher.time
      now = Time.now.to_i
      interval = now - last
      if(interval > 60)
        Watcher.log().info('db file not modified in over 60s')
        #send an e-mail
        send_email("Restarting at #{Time.now.to_s}")
        #restart the process
        
      end
      Watcher.time = now
    end
    
    def send_email additional_info
      begin
        require 'net/smtp'

        Net::SMTP.start('localhost') do |smtp|
          smtp.send_message(
            "Something's gone wrong with our project! \n\n #{additional_info} \n\n This is an automated message, but check some of the logs. #{Time.now.to_s}", 
            'senior_design@retrodict.com', 
            ['me@retrodict.com', 'brittney.exline@gmail.com', 'aagrawal@wharton.upenn.edu']
          )
        end
      rescue Errno::ECONNREFUSED
        #we couldn't connect, it's not available, so ignore it
      end
    end
  end
  
end
