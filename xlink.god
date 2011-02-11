# run by the em_mw.rb file
# God file for xlink'ers, written in ruby

require 'conf/include.rb'
require 'lib/system.rb'

[XLINK_PORT_PRIMARY, XLINK_PORT_SECONDARY].each do |port|
  God.watch do |w|
    name = "#{port}" #keep local copy of the port so it stick with this lambda
    w.name = "xlink-#{name}"
    w.interval = 30.seconds # default poll time
    
    #don't really need this because we're working programatically
    #w.pid_file = 'tmp/irc.pid'
    w.pid_file = "tmp/xlink.#{name}.pid" #interesting...need this to figure out the pid to monitor; REQUIRED
    w.behavior(:clean_pid_file)
    
    #TODO but doesn't look like it's needed w.dir = '/var/www/myapp' #working directory or just use  File.dirname(__FILE__)#; File.join
    
    #TODO why does this not work? => 'no acceptor'
    #TODO this is also going to not have access to the db stuff I think
    xlink_start = lambda do
      pid = Process.fork do
        trap("QUIT") do
          exit(0)
        end
        #start the xlinker
        sleep(10)
        tries = 0
        begin
          if name == XLINK_PORT_PRIMARY.to_s
            EmMwXlink::start_xlink_1()
          else
            EmMwXlink::start_xlink_2()
          end
        rescue RuntimeError
          sleep(10)
          tries += 1
          retry if tries < 3
        end
      end
      Process.detach(pid)
      File.open("tmp/xlink.#{name}.pid", 'w') {|f| f.write(pid) }
    end
    
    w.start = xlink_start
    w.stop = lambda {
      File.open("tmp/xlink.#{name}.pid", 'r') do |f| 
        Process.kill("QUIT", f.readline.to_i)
      end
    }
    #w.restart = xlink_start #TODO this should only be called if it's dead, but it should probably not be the same as start
    w.start_grace = 20.seconds
    w.restart_grace = 20.seconds
    
    w.start_if do |start|
      start.condition(:process_running) do |c|
        #c.interval = 100.seconds
        c.running = false
        c.notify = 'phill'
      end
    end
    
    #monitor the db file, if it's not modified within a certain time...
    #don't restart the xlink'ers, need to restart what?; notify for now
    #TODO file is hardcoded...
    # w.transition(:up, :restart) do |on|
    #       on.condition(:file_mtime) do |c|
    #         c.path = 'en_wikipedia.sqlite'
    #         c.max_age = 30.seconds #this should be way more than every time we get a sample
    #         c.notify = 'phill'
    #       end
    #     end
    
    # m = Metric.new(w)
    # m.condition(:file_mtime) do |c|
    #   c.path = 'en_wikipedia.sqlite'
    #   c.max_age = 30.seconds #this should be way more than every time we get a sample
    #   c.notify = 'phill'
    # end
    # w.conditions.each do |c|
    #   self.directory[c] = m
    # end
    # #start this on start
    # w.metrics[:start] ||= []
    # w.metrics[start_state] << m
    
    #start monitoring once we're fully started
    w.transition(:up, nil) do |on|
      on.condition(:file_mtime) do |c|
        #c.interval = 40.seconds
        c.path = 'en_wikipedia.sqlite'
        c.max_age = 30.seconds #this should be way more than every time we get a sample
        c.notify = 'phill'
      end
    end
    
    #If this watch is started or restarted five times withing 5 minutes, then unmonitor it...
    #then after ten minutes, monitor it again to see if it was just a temporary problem; 
    #if the process is seen to be flapping five times within two hours, then give up completely
    w.lifecycle do |on|
      on.condition(:flapping) do |c|
        c.to_state = [:start, :restart]
        c.times = 5
        c.within = 5.minute
        c.transition = :unmonitored
        c.retry_in = 10.minutes
        c.retry_times = 5
        c.retry_within = 2.hours
        c.notify = 'phill'
      end
    end
    
  end
end

#TODO notification: http://rubypond.com/blog/touched-by-god-process-monitoring
# God::Contacts::Email.message_settings = {
#   :from => 'god@retrodict.com'
# }
# 
# God::Contacts::Email.server_settings = {
#   :address => "localhost",
#   :port => 25,
#   :domain => "retrodict.com"
# }
# 
# God.contact(:email) do |c|
#   c.name = 'glenn'
#   c.email = 'glenn@example.com'
# end

God::Contacts::Email.defaults do |d|
  #d.delivery_method = :smtp #default
  #d.server_host = 'localhost' #default
  #d.port = 25 #default
  d.from_email = 'senior_design@retrodict.com'
  d.from_name = 'senior_design'
end

God.contact(:email) do |c|
  c.name = 'phill'
  c.group = 'student'
  c.to_email = 'me@retrodict.com'
end
