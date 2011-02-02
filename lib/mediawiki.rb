require 'cgi'
require 'uri'
require 'timeout'

module Mediawiki
  
  API_URL_EN = 'http://en.wikipedia.org/w/api.php'
  IRC_REGEXP = /\00314\[\[\00307(.*)\00314\]\]\0034\s+(.*)\00310\s+\00302.*(diff|oldid)=([0-9]+)&(oldid|rcid)=([0-9]+)\s*\003\s*\0035\*\003\s*\00303(.*)\003\s*\0035\*\003\s*\((.*)\)\s*\00310(.*)\003/
  class<<self
    def form_url(params)
      params = {:format => :xml, :action => :query}.update(params)
      #implode params to concat 
      url = '?'
      params.each do |key, value|
        #safe = URI.escape(unsafe_variable, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
        safe_key = URI.escape(key.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
        safe_value = URI.escape(value.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
        url += safe_key + '=' + safe_value + '&'
      end
      API_URL_EN + url
    end
  
    #determines if there's at least 1 link in the revision
    #returns diff text, 
    def parse_links xml_diff_unescaped
      diff_html = CGI.unescapeHTML(xml_diff_unescaped)
      doc = Hpricot(diff_html) #noked = Nokogiri.HTML(diff_html)
      linkarray = []
      doc.search('.diff-addedline').each do |td| #noked.css('.diff-addedline').each do |td| 
        revisions = []
        if(td.search('.diffchange').empty?)#if(td.css('.diffchange').empty?) #we're dealing with a full line added
          revisions << td.inner_html #td.content 
        else
          td.search('.diffchange').each do |diff| #td.css('.diffchange').each do |diff|
            revisions << diff.inner_html #diff.content
          end
        end
        #http://daringfireball.net/2010/07/improved_regex_for_matching_urls
        #%r{(?i)\b((?:https?://|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))}
        url_regex = %r{(?i)\b((?:https?://|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))}x
        #based on http://www.mediawiki.org/wiki/Markup_spec/BNF/Links
        wikilink_regex = /\[(#{url_regex}\s*(.*?))\]/
        #TOOD only look at text in the .diffchange
        #TODO pull any correctly formed links in the diff text
        #TODO on longer revisions, this regex takes FOREVER! need to simplify!
        links = {}
        revisions.each do |revision|
          #wikilinks
          
          regex_results = []
          status = Timeout::timeout(5) do
            #the following falls into infinite loops/take exponential time 
            #on certain pieces of text with the pre/post lookups, so limit it
            regex_results = revision.to_s.scan(wikilink_regex)
          end
          unless regex_results.empty?
            regex_results.each do |regex_result|
              link, desc = regex_result.compact[1..2] 
              links[link] = desc
            end
          end
        
          #interpreted links, but don't just grab the same ones as above
          #TODO come up with the right regex, we'll just eliminate the same ones for now...not efficient like n^2; okay, most edits are small
          regex_results = []
          status = Timeout::timeout(5) do
            regex_results = revision.to_s.scan(url_regex)
          end
          unless regex_results.empty?
            regex_results.each do |regex_result|
              link = regex_result.first
              links[link] = '' unless links.keys.include?(link)
            end
          end
        end
        links.each do |regex_result|
          linkarray << [regex_result[0], #link
                        regex_result[1] || ''] #description, nil with interpreted
        end
      end
      linkarray
    end
    
    #returns diff, attrs, tags
    def parse_revision xml
      doc = Hpricot(xml) #noked = Nokogiri.XML(xml) #pass it the nok'ed xml? seems a bit presumptious
      attrs = {}
      #page attrs
      doc.search('page').each do |page| #noked.css('page').each do |page| #there's only one for each of these, but if there's none by some fluke, we won't die
        page.attributes.to_hash.each do |k,v|
          attrs[k] = v
        end
      end

      #revision attrs
      doc.search('rev').each do |rev| #noked.css('rev').each do |rev|
        rev.attributes.to_hash.each do |k,v|
          attrs[k] = v
        end
      end

      #tags
      tags = []
      doc.search('tags/tag').each do |tag| #noked.css('tags').children.each do |child|
        tags << tag.inner_html
      end

      #diff attributes
      diff_elem = doc.search('diff') #diff_elem = noked.css('diff')
      diff_elem.each do |diff|
        diff.attributes.to_hash.each do |k,v|
          attrs[k] = v
        end
      end
      diff = diff_elem.size > 1 ? diff_elem.first.inner_html : diff_elem.inner_html #diff_elem.children.to_s

      #pull out the diff_xml (TODO and other stuff)
      [diff, attrs, tags]
    end
  end#end of class<<self
end
