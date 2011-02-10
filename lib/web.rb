require 'sinatra/base'

module EmMwXlink
  class FLog < File
    def write *args
      super
      flush()
    end
  end

  class EmMwXlinkStats < Sinatra::Base
    class<<self
      #class accessors
      def secret= secret
        @@secret = secret
      end
      def secret
        @@secret
      end
    end
    
    configure do
       set :logging, false
       LOGGER = FLog.open('log/web.log', 'w')
       use Rack::CommonLogger, LOGGER
    end

    get '/' do
      EmMwXlinkStats.secret + Time.now.to_s
      #templates
      
      #first sample date time, last sample date time
      #first link date time, last link date time
      #running sum of samples/links
      #do top users with edits
      #total links, total samples (absolute measure)
      #average size of sample edit
      
      #number of samples last second
      #number of samples last minute
      #number of samples last hour
      #number of samples last day
      #number of samples last week
      #number of samples last month
      #(not really applicable) number of samples last year
      
      #number of links last second
      #number of links last minute
      #number of links last hour
      #number of links last day
      #number of links last week
      #number of links last month
      
      #number of rolled back links
      #number of admin-added links
      
      #number of unique urls, domains
      #average length of pages
      #percent links with descriptions
      #max number of links/samples added per second (relative measure)
      #number of links vs. number of samples (average number of links per sample)
      #also do above vs. number of revision ids (ie number of unique revisions in links table)
      #pie chart # of links => different statuses
      #do 'punchcard': buble chart of days of week vs. hours of day, with numbers of links added per hour
      # where else can we use this paradigm? (not just on different time scales)
      
      #spider chart of overlapping max/median/mean/min on different attributes
      #if pulling in user IP => plot that on a map, do heat map for most recent with fading for less recent times
    end
  end
end