require 'rubygems'
require 'bundler/setup'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/advanced_routes'
require 'sequel'

class MyApp < Sinatra::Base
  configure do
    set :logging, true
    register Sinatra::Reloader
  end
  
  helpers do #accessible by the templates too...
    #returns a hash with paths as keys and route info in another hash keyed by name/value pairs
    def routes
      routes = {}
      self.class.each_route do |route|
        #routes[:name] = route.app.name   # "SomeSinatraApp"
        info = {}
        routes[route.path.to_s.to_sym] = info        # that's the path given as argument to get and akin
        info[:verb] = route.verb       # get / head / post / put / delete
        info[:file] = route.file       # "some_sinatra_app.rb" or something
        info[:line] = route.line       # the line number of the get/post/... statement
        info[:pattern] = route.pattern    # that's the pattern internally used by sinatra
        info[:keys] = route.keys       # keys given when route was defined
        info[:conditions] = route.conditions # conditions given when route was defined
        info[:block] = route.block      # the route's closure
      end
      routes
    end
  end
  
  before do
    @db = Sequel.sqlite 'en_wikipedia.sqlite.bak'
    #@db[:samples]
    #@db[:links]
  end
  
  get '/' do
    @site = 'site'
    @title = 'title'
    @masthead = 'masthead'
    erb(:index, :locals => {:body => 'helloo'})#, {:locals => { :body => 'helloworld and me' }}, {:locals => { :body => 'helloworld and me' }})
  end
  
  get '/map' do
    routes().keys.join(' ').to_s
  end
end

MyApp.run!

# routes
# require "sinatra/base"
# 
# 
# class Foo < Sinatra::Base
#   register Sinatra::AdvancedRoutes
# end
# require "some_sinatra_app"
# 

