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
      @notify_slack_channel = nil
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
        when /master/i
          response = "OK, I've queued a build of the `master` branch."
          scheduler.queue_a_build(BuildData.new(
              :build_type => :master,
              :repo_full_name => Config.github_webhook_repo_full_name))
        when /(?<version>v\d+\.\d+)/
          version = $~[:version]
          if Config.valid_release_versions.include?(version)
            response = "OK, I've queued a build of `#{version}` branch."
            scheduler.queue_a_build(BuildData.new(
                :build_type => :release,
                :build_version => version,
                :repo_full_name => Config.github_webhook_repo_full_name))
          else
            response = "I'm sorry, I cannot build the #{version} release branch"
          end
        when /stop/i
          if scheduler.stop_build
            response = "OK, I stopped the currently running build."
          else
            response = "There is no build running to stop."
          end
        else
          response = "Sorry#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm not sure if you want do a `master` or release branch build, or maybe `stop` any running build?"
        end
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
        case build_data.build_type
        when :pull_request
          response = "There is a pull request build in progress for https://github.com/#{build_data.repo_full_name}/pull/#{build_data.pull_request}."
        when :master
          response = "There is a build of the `master` branch of https://github.com/#{build_data.repo_full_name} in progress."
        when :release
          response = "There is a build of the `#{build_data.build_version}` branch of https://github.com/#{build_data.repo_full_name} in progress."
        end
        if queue_length == 1
          response += " There is one build in the queue."
        elsif queue_length > 1
          response += " There are #{queue_length} builds in the queue."
        end
      end
      response
    end

    def do_help
      # TODO: The repository should be a link to GitHub
      %Q(Hello#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm the *@#{@rt_client.self['name']}* build bot version #{BuildBuddy::VERSION}! I look after 3 types of build: pull request, master and release.

A pull request build happens when you make a pull request to the *#{Config.github_webhook_repo_full_name}* GitHub repository.

I can run builds of the master branch if you say `build master`. I can do builds of release branches, e.g. `build v2.3` but only for those branches that I am allowed to build.

I can stop any running build if you ask me to `stop build`, even pull request builds.  I am configured to let the *#{Config.slack_build_channel}* channel know if master or release builds are stopped.

You can also ask me for `status` and I'll tell you what's being built and what's in the queue.
)
    end

    def do_history(message)
      case message
      when /([0-9]+)/
        count = $1
      else
        count = 5
      end

      recorder = Celluloid::Actors[:recorder]
      build_datas = recorder.get_build_ids(count)

      response = "Here are the last #{count} builds:\n"
      build_datas.each do |build_data|
        # TODO: Better formatting of the date/time
        response += "A #{build_data.build_type.to_s} at #{build_data.start_time.to_s}. #{Config.server_base_uri + '/log/' + build_data._id.to_s}\n"
      end
    end

    def on_slack_hello
      user_id = @rt_client.self['id']
      map_user_id_to_name = @rt_client.users.map {|id, user| [id, user.name]}.to_h
      info "Connected to Slack as user id #{user_id} (@#{map_user_id_to_name[user_id]})"

      map_channel_name_to_id = @rt_client.channels.map {|id, channel| [channel.name, id]}.to_h
      map_group_name_to_id = @rt_client.groups.map {|id, group| [group.name, id]}.to_h
      channel = Config.slack_build_channel
      is_channel = (channel[0] == '#')

      @notify_slack_channel = (is_channel ? map_channel_name_to_id[channel[1..-1]] : map_group_name_to_id[channel])
      if @notify_slack_channel.nil?
        error "Unable to identify the slack channel #{channel}"
      else
        info "Slack notification channel is #{@notify_slack_channel} (#{channel})"
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
        when /build/i
          do_build message, from_slack_channel, slack_user_name
        when /status/i
          do_status
        when /history/
          do_history message
        when /help/i, /what can/i
          do_help
        else
          "Sorry#{from_slack_channel ? " <@#{data['user']}>" : ""}, I'm not sure how to respond."
        end
      @rt_client.message channel: data['channel'], text: response
      info "Slack message '#{message}' from #{data['channel']} handled"
    end

    def notify_channel(build_data)
      status_message = build_data.termination_type == :killed ? "was stopped" : build_data.exit_code != 0 ? "failed" : "succeeded"
      status_message += '. '

      if build_data.build_type == :pull_request
        message = "The buddy build #{status_message}"
        Celluloid::Actor[:gitter].async.set_status(
            build_data.repo_full_name, build_data.repo_sha,
            build_data.termination_type == :killed ? :failure : build_data.exit_code != 0 ? :error : :success,
            message)
        info "Pull request build #{status_message}"
      else
        status_message += "Log file at #{Config.server_base_uri + '/log/' + build_data._id.to_s}."
        if build_data.build_type == :master
          message = "A build of the `master` branch #{status_message}"
          info "`master` branch build #{status_message}"
        else
          message = "A build of the `#{build_data.build_version}` branch #{status_message}"
          info "Release branch build #{status_message}"
        end
      end

      unless @notify_slack_channel.nil?
        @rt_client.message(channel: @notify_slack_channel, text: message)
      end
    end
  end
end
