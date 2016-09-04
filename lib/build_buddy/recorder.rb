require 'rubygems'
require 'bundler'
require 'celluloid'
require 'mongo'
require 'bson'
require 'gruff'
require 'securerandom'
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
      @mongo[:builds].indexes.create_one({:create_time => -1}, :name => "reverse_order")
    end

    def record_build_data(build_data)
      builds = @mongo[:builds]
      begin
        # Do this to prevent build _id's from being sequential and so reduce risk
        # of someone guessing a valid build URL.
        build_data._id = BSON::ObjectId.from_string(SecureRandom.hex(12).to_s)
        builds.insert_one(build_data.to_h)
      rescue Mongo::Error::OperationFailure => e
        retry if e.to_s.start_with?('E11000') # Duplicate key error
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
      @mongo[:builds].find().sort(:create_time => -1).limit(limit).map do |doc|
        BuildData.new(doc)
      end
    end

    def find_report_uri
      uri = nil
      @mongo[:builds].find().sort(:create_time => -1).each do |doc|
        file_name = File.join(Config.build_output_dir, doc[:_id].to_s, "report.html")
        if File.exist?(file_name)
          uri = BuildData.server_report_uri(doc[:_id])
          break
        end
      end
      uri
    end
  end
end