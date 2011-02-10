require 'rubygems'
require 'bundler/setup'
require 'sinatra/base'
require 'sinatra/reloader'

class MyApp < Sinatra::Base
  configure do
    set :logging, true
    register Sinatra::Reloader
  end
  
  get '/' do
    'helloworld and me'
  end
  
end

MyApp.run!

# routes
# require "sinatra/base"
# require "sinatra/advanced_routes"
# 
# class Foo < Sinatra::Base
#   register Sinatra::AdvancedRoutes
# end
# require "some_sinatra_app"
# 
# SomeSinatraApp.each_route do |route|
#   puts "-"*20
#   puts route.app.name   # "SomeSinatraApp"
#   puts route.path       # that's the path given as argument to get and akin
#   puts route.verb       # get / head / post / put / delete
#   puts route.file       # "some_sinatra_app.rb" or something
#   puts route.line       # the line number of the get/post/... statement
#   puts route.pattern    # that's the pattern internally used by sinatra
#   puts route.keys       # keys given when route was defined
#   puts route.conditions # conditions given when route was defined
#   puts route.block      # the route's closure
# end
