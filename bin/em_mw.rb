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

require File.dirname(__FILE__) + '/../conf/include'
require 'getoptlong'
require 'rdoc/usage'


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
unless ['start', 'stop'].include?(action)
  puts "Unknown action (try --help)"
  exit(0)
end

if action == 'start'
  if File.exist?(PID_FILE_PATH)
    puts "Error: cannot start a bot. A pid.txt file was found. A bot may be already running."
    exit(1)
  end

  #TODO we should not fork until we setup on the same thread as where we started, we should fork after that  
  pid = Process.fork do
    trap("QUIT") do
      Mini::Bot.stop
      exit  #TODO fix exit error
    end
    begin
      require 'lib/em_irc.rb' #TODO just requiring the file starts stuff, this should be abstracted
    rescue RuntimeError => e 
      clean_pid = proc do
        if File.exist?(PID_FILE_PATH)
          #TODO don't think I need to kill the process that we forked, I believe this error does that for us
          File.delete(PID_FILE_PATH)
        end
      end
      if e.to_s == 'no acceptor' #this should be if we have starting problems
        puts 'That port is already in use. Try another'
        clean_pid.call()
      elsif e.to_s == 'nickname in use'
        puts 'That nickname is already in use. Use another.'
        clean_pid.call()
      else
        puts "Unknown erorr #{e}"
      end
      #TODO and clear pid file
    end
    #while true do end
  end
  pid_file = File.open(PID_FILE_PATH, "w")
  pid_file.write(pid.to_s)
  pid_file.close
  Process.detach(pid)
else
  unless File.exist?(PID_FILE_PATH)
    puts "Error: cannot stop the bot. No pid file exists. A bot may not have been started."
    exit(1)
  else
    pid_file = File.new(PID_FILE_PATH, "r")
    pid = pid_file.readline.to_i
    begin
      Process.kill("QUIT", pid)
    rescue Errno::ESRCH
      puts "Error: cannot stop the bot, PID does not exist. It may have already been killed, or may have exited due to an error"
      # stopping an already stopped process is considered a success (exit status 0)
    end
    pid_file.close
    File.delete(PID_FILE_PATH)
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