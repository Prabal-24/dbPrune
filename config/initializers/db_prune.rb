DBPrune=AppConfig.new
puts "testing"
require './config/db_prune/default.rb'
require "./config/db_prune/environments/#{Rails.env}.rb"