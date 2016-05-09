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
      Mongo::Logger.logger.level = ::Logger::FATAL
      mongo_uri = BuildBuddy::Config.mongo_uri
      @mongo ||= Mongo::Client.new(mongo_uri)
      info "Connected to MongoDB at '#{mongo_uri}'"
      @mongo[:builds].indexes.create_one({:start_time => -1}, :name => "reverse_build_order")
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

    def get_build_data(id)
      document = @mongo[:builds].find({ :_id => BSON::ObjectId.from_string(id) }, { :limit => 1 }).first
      if document.nil?
        return nil
      end
      BuildData.new(document)
    end

    def get_build_data_history(limit)
      @mongo[:builds].find().sort(:start_time => -1).limit(limit).map do |document|
        BuildData.new(document)
      end
    end
  end
end