# == Synopsis
#
# start.rb: Starts up an EnWikiBot and connects it to a specified IRC server and channel
#
# == Usage
#
# ruby emmw.rb [OPTIONS] ... [start|stop]
#
# -h, --help:
#    show help
# 
# start:
#    start the bot
# 
# stop:
#    stop the bot
# 
# watch: 
#    start the watcher (on a different process)
#

require File.dirname(__FILE__) + '/../conf/include'
require 'getoptlong'
require 'rdoc/usage'
require 'lib/system.rb'

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
    when '--help'
      RDoc::usage
      exit(0)
    when 'start'
  end
end

if ARGV.length != 1
  puts "Missing action (try --help)"
  exit(0)
end

action = ARGV.shift
unless ['start', 'stop'].include?(action) #we'll stop watching on stop too
  puts "Unknown action (try --help)"
  exit(0)
end

if action == 'start'
  if File.exist?(PID_FILE_PATH)
    puts "Error: cannot start a bot. A pid.txt file was found. A bot may be already running."
    exit(1)
  end

  EmMwXlink::start_db() #do this here so that the variables can be shared on all threads

  pid_xlink_1 = Process.fork do
    trap("QUIT") do #TODO does this also trap quits on the terminal where this was opened? if you start the process, do a less +F on the file, or tail it, does this get called?
      exit(0)
    end
    #start the xlinker
    EmMwXlink::start_xlink_1()
  end
  Process.detach(pid_xlink_1)
  
  pid_xlink_2 = Process.fork do
    trap("QUIT") do #TODO does this also trap quits on the terminal where this was opened? if you start the process, do a less +F on the file, or tail it, does this get called?
      exit(0)
    end
    #start the xlinker
    EmMwXlink::start_xlink_2()
  end
  Process.detach(pid_xlink_2)
  
  #TODO looks like god needs a start delay before starting to monitor; that should be specified by god; it daemonizes itself
  god = Thread.new {
    sleep(10)
    EmMwXlink::start_god()
  }
  

  #TODO we should not fork until we setup on the same thread as where we started, we should fork after that  
  pid = Process.fork do #TODO put this in a class or something, get it out of this file
    trap("QUIT") do #TODO does this also trap quits on the terminal where this was opened? if you start the process, do a less +F on the file, or tail it, does this get called?
      EmMwXlink::Bot.stop
      exit(0)  #TODO fix exit error
    end
    begin
      EmMwXlink::start_irc()
    rescue RuntimeError => e 
      #TODO also on most errors we should let it bubble up to here
      def clean_pid #TODO also do this if we haven't installed the appropriate gems
        if File.exist?(PID_FILE_PATH)
          #TODO don't think I need to kill the process that we forked, I believe this error does that for us -- make sure
          File.delete(PID_FILE_PATH)
        end
      end
      if e.to_s == 'no acceptor' #this should be if we have starting problems
        puts 'That port is already in use. Try another. Exiting.'
        clean_pid()
        exit(1)
      elsif e.to_s == 'nickname in use'
        puts 'That nickname is already in use. Use another. Exiting.'
        clean_pid()
        exit(1)
      else
        puts "Unknown error #{e}"
      end
    end
  end
  
  File.open('tmp/xlink.7890.pid', 'w') {|f| f.write(pid_xlink_1) }
  File.open('tmp/xlink.8901.pid', 'w') {|f| f.write(pid_xlink_2) }
  File.open('tmp/irc.pid', 'w') {|f| f.write(pid) }
  Process.detach(pid)
  god.join #wait to make sure god starts
else
  unless File.exist?('tmp/irc.pid')
    puts "Error: cannot stop the bot. No pid file exists. A bot may not have been started."
    exit(1)
  else
    ['xlink.7890', 'xlink.8901', 'irc'].each do |name|
      file = "tmp/#{name}.pid"
      File.open(file,'r') do |f|
        begin
          Process.kill("QUIT", f.readline.to_i)
          File.delete(file) #only delete if we s
        rescue Errno::ESRCH
          puts "Error: cannot stop one of the PIDs, PID does not exist. It may have already been killed, or may have exited due to an error"
          # stopping an already stopped process is considered a success (exit status 0)
        end
      end
    end
  end
end



#TODO
# --server hostname, -s hostname:
#    required, the hostname of the server to connect to 
#
# --channel name, -c name:
#    required, the name of the channel to connect to 
# 
# --port number, -p port:
#    the port of the server to connect to, defaults to 6667
#
# --password word, -P word:
#    the password of the server to connect to, if necessary