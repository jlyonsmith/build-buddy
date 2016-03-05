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
      builds = @mongo[:builds]
      result = builds.insert_one(build_data.to_h)
      build_data._id = result.inserted_id
    end

    def update_build_data(build_data)
      unless build_data._id.nil?
        builds = @mongo[:builds]
        builds.replace_one({ :_id => build_data._id }, build_data.to_h)
      end
    end
  end
end