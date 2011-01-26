require 'rubygems'
require 'bundler/setup'

# require gems
require 'eventmachine'


module Mini
  class Bot
    #cattr_accessor :commands, :secret
    @@commands = {}
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
        puts line + 'a'
      end 
    end
    
    def unbind
      EM.add_timer(3) do
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

Mini::Bot.start(
  :secret => 'GHMFQPKNANMNTHQDECECSCWUCMSNSHSAFRGFTHHD',
  :mini_port => 12345,
  #:web_port => 2345,
  :server => 'irc.wikimedia.org',#server,
  :port => '6667',#port,
  :user => 'yyasb',#user,
  :password => '',#password, 
  :channels => ['en.wikipedia']#[*channels]
)