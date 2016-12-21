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
          flags.push(s.lstrip.rstrip.gsub(' ', '_').to_sym)
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
        when /^master(?: +with +(?<flags>[a-z ,]+))?/i
          flags = Slacker.extract_build_flags($~[:flags])
          response = "OK, I've queued a build of the `master` branch."
          if flags.count > 0
            response += " (#{flags.join(", ")})"
          end
          scheduler.queue_a_build(BuildData.new(
              :type => :branch,
              :branch => 'master',
              :flags => flags,
              :repo_full_name => Config.github_webhook_repo_full_name,
              :started_by => slack_user_name))
        when /^(?<version>v\d+\.\d+)(?: +with +(?<flags>[a-z ,]+))?/
          flags = Slacker.extract_build_flags($~[:flags])
          version = $~[:version]
          if Config.allowed_build_branches.include?(version)
            response = "OK, I've queued a build of the `#{version}` branch."
            if flags.count > 0
              response += " (#{flags.join(", ")})"
            end
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

    def do_show_help(is_from_slack_channel, slack_user_name)
      text_for_branch_list = Config.allowed_build_branches.count > 0 ? " or " + Config.allowed_build_branches.map { |branch| "`build #{branch}`"}.join(', ') : 0

      %Q(Hello#{is_from_slack_channel ? '' : " <@#{slack_user_name}>"}, I'm the *@#{@rt_client.self['name']}* build bot v#{BuildBuddy::VERSION}!

I understand _pull requests_ and _branch builds_.

A _pull request_ build happens when you make a pull request to the `<#{BuildData::GITHUB_URL}/#{Config.github_webhook_repo_full_name}|#{Config.github_webhook_repo_full_name}>` GitHub repository.  *TIP* you can restart a failed pull request by pushing more changes to the branch.  Use `git commit --allow-empty` if you simply need to retry the build.

To do a _branch build_ you can tell me to `build master`#{text_for_branch_list}.

I will let the *#{Config.slack_build_channel}* channel know about _branch build_ activity and the *#{Config.slack_pr_channel}* channel know about _pull request_ activity.

I have lots of `show` commands:

- `show status` and I'll tell you what my status is
- `show queue` and I will show you what is in the queue to build
- `show builds` to see the last 5 builds or `show last N builds` to see a list of the last N builds
- `show report` to get a link to the latest build report, if there is one

Stop any running build with `stop build bb-xxx`.  Use `show queue` to get a valid `bb-xxx` identifier.
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
          response += "There have only been #{build_datas.count} builds"
        else
          response += "Here are the last #{build_datas.count} builds"
        end
        attachments = []
        build_datas.each do |build_data|
          text = "[`#{build_data.start_time.to_s}`]"
          branch_url, branch_name = build_data.url_and_branch_name
          text += " `<#{branch_url}|#{branch_name}>`"
          text += "\n`<#{BuildData.server_log_uri(build_data._id)}|#{build_data._id.to_s}>`"
          unless build_data.started_by.nil?
            text += " by *@#{build_data.started_by}*"
          end
          text += " #{build_data.status_verb}"
          unless build_data.stopped_by.nil?
            text += " by *@#{build_data.stopped_by}*"
          end
          text += " ran for `#{build_data.run_time}`"
          if build_data.flags.count > 0
            text += " (#{build_data.flags.join(", ")})"
          end
          attachments.push({
            :mrkdwn_in => [ :text ],
            :text => text,
            :color => build_data.termination_type == :killed ? :warning : build_data.exit_code != 0 ? :danger : :good,
          })
        end
      end
      [response, attachments]
    end

    def do_show_status
      scheduler = Celluloid::Actor[:scheduler]
      build_data = scheduler.active_build
      queue_length = scheduler.queue_length
      response = ''
      if build_data.nil?
        response = "There are no builds running"
        if queue_length == 0
          response += " and no builds in the queue."
        else
          response += " and #{queue_length} in the queue."
        end
      else
        branch_url, branch_name = build_data.url_and_branch_name
        response = "`<#{branch_url}|#{branch_name}>` `<#{build_data.server_log_uri}|#{build_data._id.to_s}>` in progress (`#{build_data.bb_id}`)"
        unless build_data.started_by.nil?
          response += " by *@#{build_data.started_by}*"
        end
        response += " running for `#{build_data.run_time}`"
        if build_data.flags.count > 0
          response += " (#{build_data.flags.join(", ")})"
        end
        response += '.'
        if queue_length == 0
          response += " No builds in the queue."
        elsif queue_length > 1
          response += " #{queue_length} build#{queue_length > 1 ? 's' : ''} in the queue."
        end
      end
      response
    end

    def do_show_queue
      build_datas = Celluloid::Actor[:scheduler].get_build_queue
      queue_length = build_datas.count
      if queue_length == 0
        response = "There are no builds in the queue."
      else
        response = "There are #{queue_length} build#{queue_length > 1 ? 's' : ''} in the queue"
        attachments = []
        build_datas.each { |build_data|
          text = "`#{build_data.bb_id}`"
          branch_url, branch_name = build_data.url_and_branch_name
          text += " `<#{branch_url}|#{branch_name}>`"
          unless build_data.started_by.nil?
            text += " by *@#{build_data.started_by}*"
          end
          if build_data.flags.count > 0
            response += " (#{build_data.flags.join(", ")})"
          end
          attachments.push({
            :mrkdwn_in => [ :text ],
            :text => text,
            :color => "#439FE0"
          })
        }
      end
      [response, attachments]
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

      response, attachments = case message
                 when /stop +build +(bb-\d+)/i
                   do_stop $1, is_from_slack_channel, slack_user_name
                 when /build +([a-z0-9, ]+)/i
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
                 when /help/i
                   do_show_help is_from_slack_channel, slack_user_name
                 when /^relay(.*)/i # This must be sent directly to build-buddy
                   do_relay $1, slack_user_name
                 else
                   "Sorry#{is_from_slack_channel ? ' ' + slack_user_name : ''}, I'm not sure how to respond."
                              end
      @rt_client.web_client.chat_postMessage(channel: data['channel'], text: response, attachments: attachments, as_user: true)
      #@rt_client.message channel: data['channel'], text: response
      info "Slack message '#{message}' from #{data['channel']} handled"
    end

    def notify_channel(build_data)
      status_verb = build_data.status_verb
      attachment_message = ''

      branch_url, branch_name = build_data.url_and_branch_name
      if build_data.type == :branch
        version = build_data.metrics["version"]
        unless version.nil?
          attachment_message += "*#{version}*\n"
        end
        info "Branch build #{status_verb}"
      else
        attachment_message += "<#{branch_url}|*#{build_data.pull_request_title}*>\n"
        info "Pull request build #{status_verb}"
      end

      message = "`<#{branch_url}|#{branch_name}>` build #{status_verb}"
      if build_data.termination_type == :killed and build_data.stopped_by != nil
        message += " by *@#{build_data.stopped_by}*"
      end
      attachment_message += "`<#{build_data.server_log_uri}|#{build_data._id.to_s}>` ran for `#{build_data.run_time}`"

      # See https://api.slack.com/docs/attachments for more information about formatting Slack attachments
      attachments = [{
          :mrkdwn_in => [ :text ],
          :text => attachment_message,
          :color => build_data.termination_type == :killed ? :warning : build_data.exit_code != 0 ? :danger : :good,
      }]

      if build_data.type == :branch
        @rt_client.web_client.chat_postMessage(channel: @build_channel_id, text: message, attachments: attachments, as_user: true) unless @build_channel_id.nil?
      else
        @rt_client.web_client.chat_postMessage(channel: @pr_channel_id, text: message, attachments: attachments, as_user: true) unless @pr_channel_id.nil?
      end
    end
  end
end
