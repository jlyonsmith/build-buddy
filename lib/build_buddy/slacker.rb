require 'rubygems'
require 'bundler'
require 'celluloid'
require 'slack-ruby-client'
require_relative './config.rb'

module BuildBuddy
  class Slacker
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize()
      @rt_client = Slack::RealTime::Client.new
      @rt_client.on :hello do
        self.on_slack_hello()
      end
      @rt_client.on :message do |data|
        self.on_slack_data(data)
      end
      @rt_client.on :error do |error|
        sub_error = error['error']
        error "Slack error #{sub_error['code']} - #{sub_error['msg']}}"
      end
      @rt_client.on :close do |event|
        raise "Slack connection was closed"
      end
      @rt_client.start_async
      @build_slack_channel = nil
      @test_slack_channel = nil
    end

    def self.get_build_flags message
      flags = []
      unless message.nil?
        message.split(',').each do |s|
          flags.push(s.lstrip.rstrip.gsub(' ', '_').to_sym)
        end
      end
      flags
    end

    def do_build(message, from_slack_channel, slack_user_name)
      response = ''
      sender_is_a_builder = (Config.slack_builders.nil? ? true : Config.slack_builders.include?('@' + slack_user_name))
      unless sender_is_a_builder
        if from_slack_channel
          response = "I'm sorry @#{slack_user_name} you are not on my list of allowed builders."
        else
          response = "I'm sorry but you are not on my list of allowed builders."
        end
      else
        scheduler = Celluloid::Actor[:scheduler]

        case message
        when /^master(?: with )?(?<flags>.*)?/i
          flags = Slacker.get_build_flags($~[:flags])
          response = "OK, I've queued a build of the `master` branch."
          scheduler.queue_a_build(BuildData.new(
              :type => :master,
              :flags => flags,
              :repo_full_name => Config.github_webhook_repo_full_name))
        when /^(?<version>v\d+\.\d+)(?: with )?(?<flags>.*)?/
          flags = Slacker.get_build_flags($~[:flags])
          version = $~[:version]
          if Config.valid_release_versions.include?(version)
            response = "OK, I've queued a build of the `#{version}` branch."
            scheduler.queue_a_build(BuildData.new(
                :type => :release,
                :branch => version,
                :flags => flags,
                :repo_full_name => Config.github_webhook_repo_full_name))
          else
            response = "I'm sorry, I am not allowed to build the `#{version}` release branch"
          end
        else
          response = "Sorry#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm not sure if you want do a `master` or release branch build"
        end
      end
      response
    end

    def do_stop
      scheduler = Celluloid::Actor[:scheduler]

      if scheduler.stop_build
        response = "OK, I stopped the currently running build."
      else
        response = "There is no build running to stop."
      end

      response
    end

    def do_status
      scheduler = Celluloid::Actor[:scheduler]
      build_data = scheduler.active_build
      queue_length = scheduler.queue_length
      response = ''
      if build_data.nil?
        response = "There is currently no build running"
        if queue_length == 0
          response += " and no builds in the queue."
        else
          response += " and #{queue_length} in the queue."
        end
      else
        case build_data.type
        when :pull_request
          response = "There is a pull request build in progress for https://github.com/#{build_data.repo_full_name}/pull/#{build_data.pull_request}."
        when :master
          response = "There is a build of the `master` branch of https://github.com/#{build_data.repo_full_name} in progress."
        when :release
          response = "There is a build of the `#{build_data.branch}` branch of https://github.com/#{build_data.repo_full_name} in progress."
        end
        if queue_length == 1
          response += " There is one build in the queue."
        elsif queue_length > 1
          response += " There are #{queue_length} builds in the queue."
        end
      end
      response
    end

    def do_help from_slack_channel
      # TODO: The repository should be a link to GitHub
      %Q(Hello#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm the *@#{@rt_client.self['name']}* build bot version #{BuildBuddy::VERSION}! I look after 3 types of build: pull request, master and release.

A pull request build happens when you make a pull request to the *#{Config.github_webhook_repo_full_name}* GitHub repository.

I can run builds of the master branch if you say `build master`. I can do builds of release branches, e.g. `build v2.3` but only for those branches that I am allowed to build.

I can stop any running build if you ask me to `stop build`, even pull request builds.  I am configured to let the *#{Config.slack_build_channel}* channel know if master or release builds are stopped.

You can also ask me for `status` and I'll tell you what's being built.

Ask me `what happened` to get a list of recent builds and log files and `what options` to see the list of options for running builds.
)
    end

    def do_what(question)
      question = question.lstrip.rstrip

      case question
      when /happened/
        case question
        when /([0-9]+)/
          limit = $1.to_i
        else
          limit = 5
        end

        recorder = Celluloid::Actor[:recorder]
        build_datas = recorder.get_build_data_history(limit)

        if build_datas.count == 0
          response = "No builds have performed yet"
        else
          response = "Here are the last #{build_datas.count} builds:\n"
          build_datas.each do |build_data|
            response += "A "
            response += case build_data.type
                        when :master
                          "`master` branch build"
                        when :release
                          "`#{build_data.branch}` release branch build"
                        when :pull_request
                          "pull request `#{build_data.pull_request}` build"
                        end
            response += " at #{build_data.start_time.to_s}. #{Config.server_base_uri + '/log/' + build_data._id.to_s}\n"
          end
        end
      when /options/
        response = %Q(You can add the following options to builds:
- *test channel* to have notifications go to the test channel
- *no upload* to not have the build upload
)
      else
        response = "I'm not sure what to say..."
      end
      response
    end

    def self.get_channel_id(channel, map_channel_name_to_id, map_group_name_to_id)
      (channel.start_with?('#') ? map_channel_name_to_id[channel[1..-1]] : map_group_name_to_id[channel])
    end

    def on_slack_hello
      user_id = @rt_client.self['id']
      map_user_id_to_name = @rt_client.users.map {|id, user| [id, user.name]}.to_h
      info "Connected to Slack as user id #{user_id} (@#{map_user_id_to_name[user_id]})"

      map_channel_name_to_id = @rt_client.channels.map {|id, channel| [channel.name, id]}.to_h
      map_group_name_to_id = @rt_client.groups.map {|id, group| [group.name, id]}.to_h

      @build_slack_channel = Slacker.get_channel_id(Config.slack_build_channel, map_channel_name_to_id, map_group_name_to_id)

      if @build_slack_channel.nil?
        error "Unable to identify the build slack channel #{channel}"
      else
        info "Slack build notification channel is #{@build_slack_channel} (#{Config.slack_build_channel})"
      end

      @test_slack_channel = Slacker.get_channel_id(Config.slack_test_channel, map_channel_name_to_id, map_group_name_to_id)

      if @test_slack_channel.nil?
        error "Unable to identify the test slack channel #{channel}"
      else
        info "Slack test notification channel is #{@test_slack_channel} (#{Config.slack_test_channel})"
      end
    end

    def on_slack_data(data)
      message = data['text']

      # If no message, then there's nothing to do
      if message.nil?
        return
      end

      slack_user_id = data['user']

      # Only respond to messages from users and bots
      if slack_user_id.nil?
        if data['username'].nil? or data['subtype'] != 'bot_message'
          return
        end
        slack_user_name = data['username']
      else
        map_user_id_to_name = @rt_client.users.map {|id, user| [id, user.name]}.to_h
        slack_user_name = map_user_id_to_name[slack_user_id]

        if slack_user_name.nil?
          error "User #{slack_user_id} is not known"
          return
        end
      end

      # Don't respond if _we_ sent the message!
      if slack_user_id == @rt_client.self['id']
        return
      end

      c = data['channel'][0]
      from_slack_channel = (c == 'C' || c == 'G')

      # Don't respond if the message is to a channel and our name is not in the message
      if from_slack_channel and !message.match(@rt_client.self['id'])
        return
      end

      response = case message
        when /build (.*)/i
          do_build $1, from_slack_channel, slack_user_name
        when /status/i
          do_status
        when /what(.*)/
          do_what $1
        when /help/i, /what can/i
          do_help from_slack_channel
        when /stop/i
          do_stop
        else
          "Sorry#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm not sure how to respond."
        end
      @rt_client.message channel: data['channel'], text: response
      info "Slack message '#{message}' from #{data['channel']} handled"
    end

    def notify_channel(build_data)
      status_message = build_data.termination_type == :killed ? "was stopped" : build_data.exit_code != 0 ? "failed" : "succeeded"
      status_message += '. '
      log_url = Config.server_base_uri + '/log/' + build_data._id.to_s

      if build_data.type == :pull_request
        message = "Build #{status_message}"
        git_state = (build_data.termination_type == :killed ? :failure : build_data.exit_code != 0 ? :error : :success)
        Celluloid::Actor[:gitter].async.set_status(build_data.repo_full_name, build_data.repo_sha, git_state, message, log_url)
        info "Pull request build #{status_message}"
      else
        status_message += "Log file at #{log_url}."
        if build_data.type == :master
          message = "A build of the `master` branch #{status_message}"
          info "`master` branch build #{status_message}"
        else
          message = "A build of the `#{build_data.branch}` branch #{status_message}"
          info "Release branch build #{status_message}"
        end

        # See https://api.slack.com/docs/attachments for more information about formatting Slack attachments
        attach = [
            :title => build_data.type == :pull_request ? "Pull Request" : "Branch Build",
            :text => message,
            :color => build_data.termination_type == :killed ? :warning : build_data.exit_code != 0 ? :danger : :good,
        ]

        if build_data.flags.include?(:test_channel)
          unless @test_slack_channel.nil?
            @rt_client.message(channel: @test_slack_channel, attachments: attach)
          end
        else
          unless @build_slack_channel.nil?
            @rt_client.message(channel: @build_slack_channel, attachments: attach)
          end
        end
      end
    end
  end
end
