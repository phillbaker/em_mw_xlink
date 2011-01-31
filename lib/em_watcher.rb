require 'logger'
require 'sqlite3'
require 'rubygems'
require 'bundler/setup'

# require bundled gems
require 'eventmachine'

class EmWatcher #TODO in the future, this should just kick stuff off, it's the same code...
  def self.start
    Watcher.time = Time.now.to_i #should initialize to starting time
    log = Logger.new("#{LOG_DIR_PATH}/watcher.log")
    Watcher.log = log
    
    EM.kqueue = true if EM.kqueue?
    EventMachine.run do
      EventMachine.watch_file("#{LOG_DIR_PATH}/../en_wikipedia.sqlite", Watcher) #TODO don't hardwire this
      EventMachine.add_periodic_timer(30) do #test#10) do #check every 10s
        interval = Time.now.to_i - Watcher.time
        log.info("db file modified after: #{interval}")
        if(true)#test doing it anyways; interval > 30)
          log.info('db file not modified in over 60s')
          #restart the process
          #kill the old process
          pid_file = File.new('tmp/pid.txt', 'r')#TODO use the same constants
          pid = pid_file.readline.to_i
          begin
            Process.kill("QUIT", pid)
            log.info("killed the process #{pid}")
          rescue Errno::ESRCH
            #TODO, then what do do?
            log.info('couldn\'t kill the process')
          end
          pid_file.close
          
          sleep(2) #give it some time to exit
          
          #start a new one
          pid = Process.fork do #TODO put this in a class or something, get it out of this file
            trap("QUIT") do #TODO does this also trap quits on the terminal where this was opened? if you start the process, do a less +F on the file, or tail it, does this get called?
              Mini::Bot.stop
              exit(0)  #TODO fix exit error
            end
            begin
              #puts $LOAD_PATH
              #p ENV
              #fix ENV to go back to before bundler/setup from the previous calling...
              # ENV.delete('GEM_HOME')
              # ENV.delete('GEM_PATH')
              # ENV.delete('BUNDLE_BIN_PATH')
              # ENV.delete('RUBYOPT')
              # ENV.delete('BUNDLE_GEMFILE')

              require 'lib/em_irc.rb' #TODO just requiring the file starts stuff, this should be abstracted
              #eventmachine doens't block - it's all callbacks on another thread, so we should get here
            rescue RuntimeError => e 
              #TODO also on most errors we should let it bubble up to here
              def clean_pid #TODO also do this if we haven't installed the appropriate gems
                if File.exist?('tmp/pid.txt')
                  #TODO don't think I need to kill the process that we forked, I believe this error does that for us -- make sure
                  File.delete('tmp/pid.txt')
                end
              end
              if e.to_s == 'no acceptor' #this should be if we have starting problems
                puts 'That port is already in use. Try another. Exiting.'
                clean_pid()
              elsif e.to_s == 'nickname in use'
                puts 'That nickname is already in use. Use another. Exiting.'
                clean_pid()
              else
                puts "Unknown erorr #{e}"
              end
            end
          end
          log.info("restarted at #{pid}")

          pid_file = File.open('tmp/pid.txt', "w")
          pid_file.write("#{pid}\n#{Process.pid}")
          pid_file.close
          Process.detach(pid)
          
          #send an e-mail
          EmWatcher.send_email("Restarting at #{Time.now.to_s}")


        end
      end
      
    end
  end
  
  def self.stop
    EventMachine.stop
  end

  def self.send_email additional_info
    begin
      require 'net/smtp'

      Net::SMTP.start('localhost') do |smtp|
        smtp.send_message(
          "Something's gone wrong with our project! \n\n #{additional_info} \n\n This is an automated message, but check some of the logs. #{Time.now.to_s}", 
          'senior_design@retrodict.com', 
          ['me@retrodict.com']#, 'brittney.exline@gmail.com', 'aagrawal@wharton.upenn.edu']
        )
      end
    rescue Errno::ECONNREFUSED
      #we couldn't connect, it's not available, so ignore it
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
      Watcher.log().info('db file modified')
      Watcher.time = Time.now.to_i
    end
    
  end
  
end
