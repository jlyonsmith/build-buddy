require 'rubygems'
require 'bundler'
require 'celluloid'
require 'mongo'
require_relative './config.rb'

module BuildBuddy
  class Recorder
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize()
      @mongo ||= Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'build-buddy')
      info "Connected to MongoDB"
    end

    def record_build_data(build_data)
      builds = @mongo[:builds].insert_one(build_data.attributes)
    end
  end
end