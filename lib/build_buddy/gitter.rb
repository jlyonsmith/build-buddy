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

    # state is one of :pending, :killed, :failure, :error, :success
    def set_status(repo_full_name, repo_sha, state, description, target_url)
      options = {
        :description => description.length > 140 ? "#{description[0..136]}..." : description,
        :context => 'build-buddy',
        :target_url => target_url || ''
      }
      @gh_client.create_status(repo_full_name, repo_sha, state.to_s, options)
    end
  end
end
