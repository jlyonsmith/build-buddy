require 'rubygems'
require 'bundler'
require 'celluloid'
require 'mongo'
require 'gruff'
require_relative './config.rb'

module BuildBuddy
  class Recorder
    include Celluloid
    include Celluloid::Internals::Logger

    LIMIT = 50

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
      if build_data._id.nil?
        build_data._id = result.inserted_id
      end
    end

    def update_build_data(build_data)
      if build_data._id.nil?
        return
      end

      builds = @mongo[:builds]
      builds.replace_one({ :_id => build_data._id }, build_data.to_h)
    end

    def get_build_data(id)
      doc = @mongo[:builds].find({ :_id => BSON::ObjectId.from_string(id) }, { :limit => 1 }).first
      if doc.nil?
        return nil
      end
      BuildData.new(doc)
    end

    def get_build_data_history(limit)
      @mongo[:builds].find().sort(:start_time => -1).limit(limit).map do |doc|
        BuildData.new(doc)
      end
    end
  end
end