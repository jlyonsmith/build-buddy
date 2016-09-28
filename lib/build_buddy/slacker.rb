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
      @rt_client = Slack::RealTime::Client.new(websocket_ping: 3)
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
      @rt_client.on :closed do |event|
        info "Slack connection was closed"
        self.terminate
      end

      begin
        @rt_client.start_async
      rescue Exception => e
        info "Unable to connect to Slack - #{e.message}"
        self.terminate
      end

      @build_channel_id = nil
      @pr_channel_id = nil
    end

    def self.extract_build_flags(message)
      flags = []
      unless message.nil?
        message.split(',').each do |s|
          flags.push(s.lstrip.rstrip.downcase.gsub(' ', '_').to_sym)
        end
      end
      flags
    end

    def do_build(message, is_from_slack_channel, slack_user_name)
      response = ''
      sender_is_a_builder = (Config.slack_builders.nil? ? true : Config.slack_builders.include?('@' + slack_user_name))
      unless sender_is_a_builder
        if is_from_slack_channel
          response = "I'm sorry @#{slack_user_name} you are not on my list of allowed builders."
        else
          response = "I'm sorry but you are not on my list of allowed builders."
        end
      else
        scheduler = Celluloid::Actor[:scheduler]
        message = message.strip

        case message
        when /^master(?: +with +(?<flags>[a-z ]+))?/i
          flags = Slacker.extract_build_flags($~[:flags])
          response = "OK, I've queued a build of the `master` branch."
          scheduler.queue_a_build(BuildData.new(
              :type => :branch,
              :branch => 'master',
              :flags => flags,
              :repo_full_name => Config.github_webhook_repo_full_name,
              :started_by => slack_user_name))
        when /^(?<version>v\d+\.\d+)(?: with )?(?<flags>.*)?/
          flags = Slacker.extract_build_flags($~[:flags])
          version = $~[:version]
          if Config.allowed_build_branches.include?(version)
            response = "OK, I've queued a build of the `#{version}` branch."
            scheduler.queue_a_build(BuildData.new(
                :type => :branch,
                :branch => version,
                :flags => flags,
                :repo_full_name => Config.github_webhook_repo_full_name,
                :started_by => slack_user_name))
          else
            response = "I'm sorry, I am not allowed to build the `#{version}` branch"
          end
        else
          response = "Sorry#{is_from_slack_channel ? ' @' + slack_user_name : ''}, I'm not sure if you want do a `master` or release branch build"
        end
      end
      response
    end

    def do_stop(bb_id, is_from_slack_channel, slack_user_name)
      response = ''
      unless bb_id.nil?
        bb_id = bb_id.upcase
        result = Celluloid::Actor[:scheduler].stop_build(bb_id, slack_user_name)
        case result
        when :active, :in_queue
          response = "OK#{is_from_slack_channel ? ' @' + slack_user_name : ''}, I #{result == :active ? 'stopped' : 'dequeued'} the build with identifier #{bb_id}."
          info "Build #{bb_id} was stopped by #{slack_user_name}"
        when :not_found
          response = "I could not find a queued or active build with that identifier"
        end
      else
        response = "You must specify the build identifier. It can be an active build or a build in the queue."
      end

      response
    end

    def do_show_help(is_from_slack_channel)
      %Q(Hello#{is_from_slack_channel ? " <@#{data['user']}>" : ""}, I'm the *@#{@rt_client.self['name']}* build bot version #{BuildBuddy::VERSION}!

I understand types of build - pull requests and branch. A pull request build happens when you make a pull request to the https://github.com/#{Config.github_webhook_repo_full_name} GitHub repository.

For branch builds, I can run builds of the master branch if you say `build master`. I can do builds of release branches, e.g. `build v2.3` but only for those branches that I am allowed to build in by configuration file.

I can stop any running build if you ask me to `stop build X`, even pull request builds if you give the id X from the `show status` or `show queue` command.

I will let the *#{Config.slack_build_channel}* channel know about branch build activity and the *#{Config.slack_pr_channel} channel know about PR activity.

I have lots of `show` commands:

- `show status` and I'll tell you what my status is
- `show queue` and I will show you what is in the queue
- `show options` to a see a list of build options
- `show builds` to see the last 5 builds or `show last N builds` to see a list of the last N builds
- `show report` to get a link to the latest build report
)
    end

    def do_relay(message, slack_user_name)
      sender_is_a_builder = (Config.slack_builders.nil? ? true : Config.slack_builders.include?('@' + slack_user_name))
      unless sender_is_a_builder
        if is_from_slack_channel
          response = "I'm sorry @#{slack_user_name} you are not on my list of allowed builders so I can't relay a message for you."
        else
          response = "I'm sorry but you are not on my list of allowed builders so I cannot relay a message for you."
        end
      else
        message = message.strip.gsub('"', '')
        @rt_client.message(channel: @build_channel_id, text: message) unless @build_channel_id.nil?
      end
      "Message relayed to #{Config.slack_build_channel}"
      info "I relayed a message for #{slack_user_name} to #{Config.slack_build_channel}, \"#{message}\""
    end

    def do_show_builds(limit)
      build_datas = Celluloid::Actor[:recorder].get_build_data_history(limit)

      if build_datas.count == 0
        response = "No builds have performed yet"
      else
        response = ''
        if build_datas.count < limit
          response += "There have only been #{build_datas.count} builds:\n"
        else
          response += "Here are the last #{build_datas.count} builds:\n"
        end
        build_datas.each do |build_data|
          response += "A "
          response += case build_data.type
                      when :branch
                        "`#{build_data.branch}` branch build"
                      when :pull_request
                        "pull request build #{build_data.pull_request_uri}"
                      end
          response += " at #{build_data.start_time.to_s}. #{BuildData.server_log_uri(build_data._id)}"
          unless build_data.started_by.nil?
            response += " started by #{build_data.started_by}"
          end
          response += " #{build_data.status_verb}"
          unless build_data.stopped_by.nil?
            response += " by #{build_data.stopped_by}"
          end
          response += ".\n"
        end
      end
      response
    end

    def do_show_status
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
          response = "There is a pull request build in progress for https://github.com/#{build_data.repo_full_name}/pull/#{build_data.pull_request} (#{build_data.bb_id})"
        when :branch
          response = "There is a build of the `#{build_data.branch}` branch of https://github.com/#{build_data.repo_full_name} in progress (#{build_data.bb_id})"
        end
        unless build_data.started_by.nil?
          response += " started by " + build_data.started_by
        end
        unless build_data.stopped_by.nil?
          response += " stopped by #{build_data.stopped_by}"
        end
        response += '.'
        if queue_length == 1
          response += " There is one build in the queue."
        elsif queue_length > 1
          response += " There are #{queue_length} builds in the queue."
        end
      end
      response
    end

    def do_show_options
      %Q(You can add the following options to builds:
- *test channel* to have notifications go to the test channel
- *no upload* to not have the build upload
)
    end

    def do_show_queue
      build_datas = Celluloid::Actor[:scheduler].get_build_queue
      if build_datas.count == 0
        response = "There are no builds in the queue."
      else
        response = 'The following builds are in the queue:\n'
        build_datas.each { |build_data|
          response += "- #{build_data.bb_id}, a "
          response += case build_data.type
                      when :branch
                        "`#{build_data.branch}` branch build"
                      when :pull_request
                        "pull request build #{build_data.pull_request_uri}"
                      end
          unless build_data.started_by.nil?
            response += " started by #{build_data.started_by}"
          end
          response += ".\n"
        }
      end
      response
    end

    def do_show_report
      response = ''
      report_uri = Celluloid::Actor[:recorder].find_report_uri
      if report_uri.nil?
        response = "There do not appear to be any reports generated yet"
      else
        response = "The last build report is at #{report_uri}"
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

      @build_channel_id = Slacker.get_channel_id(Config.slack_build_channel, map_channel_name_to_id, map_group_name_to_id)

      if @build_channel_id.nil?
        error "Unable to identify the slack build channel #{Config.slack_build_channel}"
      else
        info "Slack build notification channel is #{@build_channel_id} (#{Config.slack_build_channel})"
      end

      @pr_channel_id = Slacker.get_channel_id(Config.slack_pr_channel, map_channel_name_to_id, map_group_name_to_id)

      if @pr_channel_id.nil?
        error "Unable to identify the PR slack channel #{Config.slack_pr_channel}"
      else
        info "Slack PR notification channel is #{@pr_channel_id} (#{Config.slack_pr_channel})"
      end
    end

    def on_slack_data(data)
      # Don't respond to ephemeral messages from Slack
      if data['is_ephemeral']
        return
      end

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
      is_from_slack_channel = (c == 'C' || c == 'G')

      # Don't respond if the message is from a channel and our name is not in the message
      if is_from_slack_channel and !message.match(@rt_client.self['id'])
        return
      end

      message = message.strip

      response = case message
                 when /stop +build +(bb-\d+)/i
                   do_stop $1, is_from_slack_channel, slack_user_name
                 when /build +([a-z0-9\.]+)/i
                   do_build $1, is_from_slack_channel, slack_user_name
                 when /(?:show +)?status/
                   do_show_status
                 when /show +(?:last +([0-9]+) +)?builds/
                   limit = $1.to_i unless $1.nil?
                   if limit.nil? or limit < 5
                     limit = 5
                   end
                   do_show_builds limit
                 when /show report/
                   do_show_report
                 when /show queue/
                   do_show_queue
                 when /show options/
                   do_show_options
                 when /help/i
                   do_show_help is_from_slack_channel
                 when /^relay(.*)/i # This must be sent directly to build-buddy
                   do_relay $1, slack_user_name
                 else
                   "Sorry#{is_from_slack_channel ? ' ' + slack_user_name : ''}, I'm not sure how to respond."
                 end
      @rt_client.message channel: data['channel'], text: response
      info "Slack message '#{message}' from #{data['channel']} handled"
    end

    def notify_channel(build_data)
      status_verb = build_data.status_verb

      if build_data.type == :branch
        message = "A `#{build_data.branch}` branch build #{status_verb}"
        short_message = message
        info "Branch build #{status_verb}"
      else
        message = "Pull request <https://github.com/#{build_data.repo_full_name}/pull/#{build_data.pull_request}|#{build_data.pull_request_title}> build #{status_verb}"
        short_message = "Pull request #{build_data.pull_request} #{status_verb}"
        info "Pull request build #{status_verb}"
      end

      if build_data.termination_type == :killed and build_data.stopped_by != nil
        message += " by #{build_data.stopped_by}"
      end

      message += ". Log file at #{build_data.server_log_uri}"

      # See https://api.slack.com/docs/attachments for more information about formatting Slack attachments
      attachments = [
          :title => build_data.type == :pull_request ? "Pull Request" : "Branch Build",
          :text => message,
          :color => build_data.termination_type == :killed ? :warning : build_data.exit_code != 0 ? :danger : :good,
      ]

      if build_data.type == :branch
        @rt_client.web_client.chat_postMessage(channel: @build_channel_id, text: short_message, attachments: attachments, as_user: true) unless @build_channel_id.nil?
      else
        @rt_client.web_client.chat_postMessage(channel: @pr_channel_id, text: short_message, attachments: attachments, as_user: true) unless @pr_channel_id.nil?
      end
    end
  end
end
