require 'logger'
require 'bundler/setup'
require 'hpricot'
require 'eventmachine'
require 'em-http'
require 'sqlite3'

require 'mediawiki.rb'

module EmMwXlink
  @@xlink_log = Logger.new('log/xlink.log')
  class<<self
    def follow_revision fields
      #get the xml from wikipedia
      url = Mediawiki::form_url({:prop => :revisions, :revids => fields[:revision_id], :rvdiffto => 'prev', :rvprop => 'ids|flags|timestamp|user|size|comment|parsedcomment|tags|flagged' })
      #TODO wikipeida requires a User-Agent header, and we didn't supply one, so em-http must...
      EventMachine::HttpRequest.new(url).get(:timeout => 5).callback do |http|
        done = false
        begin
          xml = http.response.to_s
          #parse the xml
          raise Exception.new('trying to parse nothing') unless xml.size > 0
          doc = Hpricot(xml)
          #test to see if we have a badrevid
          bad_revs = doc.search('badrevids')
          if bad_revs.first == nil
            diff, attrs, tags = Mediawiki::parse_revision(xml) #don't really like doing this transformation twice...

            #parse it for links
            links = Mediawiki::parse_links(diff)
            #if there are links, investigate!
            unless links.empty?
              #pulling the source via EM shouldn't block...
              links.each do |url_and_desc|
                url = url_and_desc.first
                url_regex = /^(.*?\/\/)([^\/]*)(.*)$/x
                #deal with links stargin with 'www', if they get entered into wikilinks like that they count!
                unless url =~ url_regex
                  url = "http://#{url}"
                end
                #TODO instead do something like html unescaping the url and then re-parsing it, that shouldn't unescape the url too
                url = url.gsub(%r{&lt;/ref&gt$}, '') #if we end in '&lt;/ref&gt', then strip that; little hacky but problem from the url parsing
                
                revision_id = fields[:revision_id]
                description = url_and_desc.last
                if url =~ %r{^http://} #TODO ignore not http protocol links for now (including https)
                  #@@xlink_log.info("#{fields[:revision_id]}: #{url}")
                  follow_link(revision_id, url, description)
                else
                  @@xlink_log.info("would have followed link: #{url}")
                end
              end # end links each
            else
              #@@xlink_log.info("no links")
            end #end unless (following link)
          else
            @@xlink_log.error "badrevids: #{bad_revs.inner_html.to_s}"
          end #end bad revid check
          done = true
        rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@xlink_log.error "problem following revision: #{e}"
          @@xlink_log.error e.backtrace.join("\n") if e.backtrace
        ensure
          @@xlink_log.error("broken at following revisions") unless done
        end #end rescue
  
      end #end em-http
    end #end follow-revisions


    def follow_link revision_id, url, description
      #TODO test to see if these redirects/timeouts are too small/what happens if they do timeout/run out of redirections?
      EventMachine::HttpRequest.new(url).get(:redirects => 5, :timeout => 5).callback do |http|
        begin
          #shallow copy all reponse headers to a hash with lowercase symbols as keys
          #em-http converts dashs to symbols
          headers = http.response_header.inject({}){|memo,(k,v)| memo[k.to_s.downcase.to_sym] = v; memo}
          #ignore binary, non content-type text/html files
          if(headers[:content_type] =~ /^text\/html/ )
            @@xlink_log.info("storing #{revision_id}: #{url}")
            EmMwXlink::db.call(:insert_link, 
              :source => http.response.to_s.gsub(/\x00/, ''), #take out null characters, just in case
              :headers => Marshal.dump(headers),
              :url => url,
              :revision_id => revision_id,
              :wikilink_description => description,
              :status => http.response_header.status,
              :last_effective_url => http.last_effective_url.to_s
            )
      	  else
            fields = {
              :source => 'non-html', 
              :headers => Marshal.dump(headers), 
              :url => url, 
              :revision_id => revision_id, 
              :wikilink_description => description,
              :status => http.response_header.status,
              :last_effective_url => http.last_effective_url.to_s
            }

            link_table = EmMwXlink::db[:links]
        	  link_table << fields
    	    end
        rescue EventMachine::ConnectionNotBound, SQLite3::SQLException, Exception => e
          @@xlink_log.error "Followed link: #{e}"
          @@xlink_log.error "Followed link: #{e.backtrace}"
        end #end rescue
      end #end em-http
    end
  end
  #this is the unstable version and we're going to monitor whether they're available on different ports
  module RevisionReceiver
    include EventMachine::Protocols::ObjectProtocol
    
    def receive_object(revision_hash)
      EmMwXlink::follow_revision(revision_hash)
    end
    
  end
  
end