require 'rubygems'
require 'bundler'
require 'celluloid'
require 'octokit'
require_relative './config.rb'

module BuildBuddy
  class Gitter
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize()
      @gh_client ||= Octokit::Client.new(:access_token => Config.github_api_token)
      info "Connected to Github"
    end

    def set_status(repo_full_name, repo_sha, status, description, target_url)
      options = {
          :description => description.length > 140 ? "#{description[0..136]}..." : description,
          :context => 'build-buddy'
      }
      unless target_url.nil?
        options[:target_url] = target_url
      end
      @gh_client.create_status(repo_full_name, repo_sha, status.to_s, options)
    end
  end
end
