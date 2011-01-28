module Mediawiki
  
  API_URL_EN = 'http://en.wikipedia.org/w/api.php'
  IRC_REGEXP = /\00314\[\[\00307(.*)\00314\]\]\0034\s+(.*)\00310\s+\00302.*(diff|oldid)=([0-9]+)&(oldid|rcid)=([0-9]+)\s*\003\s*\0035\*\003\s*\00303(.*)\003\s*\0035\*\003\s*\((.*)\)\s*\00310(.*)\003/
  
  def form_url(params)
    params = {:format => :xml, :action => :query}.update(params)
    #implode params to concat 
    url = '?'
    params.each do |key, value|
      #val = URI.escape(unsafe_variable, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      safe_key = URI.escape(key.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      safe_value = URI.escape(value.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      url += safe_key + '=' + safe_value + '&'
    end
    API_URL_EN + url
  end
  
  
end