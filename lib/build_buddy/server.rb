require 'bundler/setup'
require 'celluloid/current'
require 'reel'
require 'slack-ruby-client'
require 'json'
require 'ostruct'
require 'octokit'
require 'thread'
require 'timers'
require 'rack'
require_relative './builder.rb'

module BuildBuddy
  class Server < Reel::Server::HTTP
    include Celluloid::Internals::Logger

    def initialize(host = "127.0.0.1", port = 4567)
      super(host, port, &method(:on_connection))
      @gh_client ||= Octokit::Client.new(:access_token => Config.github_api_token)
      @rt_client = Slack::RealTime::Client.new
      @rt_client.on :hello do
        self.on_slack_hello()
      end
      @rt_client.on :message do |data|
        self.on_slack_data(data)
      end
      @rt_client.on :error do |error|
        self.on_slack_error(error)
      end
      @rt_client.start_async
      @active_build = nil
      @build_queue = Queue.new
      @done_queue = Queue.new
      @notify_slack_channel = nil
    end

    def on_slack_error(error)
      sub_error = error['error']
      error "Whoops! Slack error #{sub_error['code']} - #{sub_error['msg']}}"
    end

    def on_slack_hello
      info "Connected to Slack as user #{@rt_client.self['id']}"

      channel_map = @rt_client.channels.map {|channel| [channel['name'], channel['id']]}.to_h

      @notify_slack_channel = channel_map[Config.slack_build_channel]
    end

    def on_slack_data(data)
      message = data['text']

      # If no message, then there's nothing to do
      if message.nil?
        return
      end

      # Don't respond if _we_ sent the message!
      if data['user'] == @rt_client.self['id']
        return
      end

      in_channel = (data['channel'][0] == 'C')

      # Don't respond if the message is to a channel and our name is not in the message
      if in_channel and !message.match(@rt_client.self['id'])
        return
      end

      case message
        when /build/i
          case message
            when /master/i
              response = "OK, I've queued a build of the `master` branch."
              queue_a_build(OpenStruct.new(
                  :build_type => :internal,
                  :repo_full_name => Config.github_webhook_repo_full_name))
            when /(?<version>v\d+\.\d+)/
              version = $~[:version]
              response = "OK, I've queued a build of `#{version}` branch."
              queue_a_build(OpenStruct.new(
                  :build_type => :external,
                  :build_version => version,
                  :repo_full_name => Config.github_webhook_repo_full_name))
            when /stop/i
              build_data = @active_build
              if build_data.nil?
                response = "There is no build running to stop"
              else
                # TODO: We need some more checks here to avoid accidental stoppage
                response = "OK, I'm trying to *stop* the currently running build..."
                Celluloid::Actor[:builder].async.stop_build
              end
            else
              response = "Sorry#{in_channel ? " <@#{data['user']}>" : ""}, I'm not sure if you want do an internal *master*, external *M.m* build, or maybe *stop* any running build?"
          end
        when /status/i
          build_data = @active_build
          queue_length = @build_queue.length
          if build_data == nil
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
              when :internal
                response = "There is an build of the `master` branch of https://github.com/#{build_data.repo_full_name} in progress."
              when :external
                response = "There is an build of the `#{build_data.build_version}` branch of https://github.com/#{build_data.repo_full_name} in progress."
            end
            if queue_length == 1
              response += " There is one build ahead of it."
            elsif queue_length > 1
              response += " There are #{queue_length} builds ahead of it."
            end
          end
        when /help/i, /what can/i
          # TODO: The repository should be a link to GitHub
          response = %Q(Hello#{in_channel ? " <@#{data['user']}>" : ""}, I'm the *@#{@rt_client.self['name']}* build bot! I look after 3 types of build: pull request, master and release.

  A pull request *build* happens when you make a pull request to the *#{Config.github_webhook_repo_full_name}* GitHub repository. I can stop those builds if you ask me too through Slack, but you have to start them with a pull request.

  I can run builds of the *master* branch when you ask me, as well as doing builds of a release branch, e.g. *v2.0*, *v2.3*, etc..

  You can also ask me about the *status* of builds and I'll tell you if anything is currently happening.

  I am configured to let the *\##{Config.slack_build_channel}* channel know if internal or external builds fail. Note the words I have highlighted in bold. These are the keywords that I'll look for to understand what you are asking me.
  )
        else
          response = "Sorry#{in_channel ? " <@#{data['user']}>" : ""}, I'm not sure how to respond."
      end
      @rt_client.message channel: data['channel'], text: response
      info "Slack message '#{message}' from #{data['channel']} handled"
    end

    def on_connection(connection)
      connection.each_request do |request|
        case request.method
        when 'POST'
          case request.path
          when '/webhook'
            case request.headers["X-GitHub-Event"]
              when 'pull_request'
                info "Got a pull request from GitHub"
                payload_text = request.body.to_s
                # TODO: Also need to validate that it's the github_webhook_repo_full_name
                if !verify_signature(payload_text, request.headers["X-Hub-Signature"])
                  request.response 500, "Signatures didn't match!"
                else
                  payload = JSON.parse(payload_text)
                  pull_request = payload['pull_request']
                  build_data = OpenStruct.new(
                    :build_type => :pull_request,
                    :pull_request => pull_request['number'],
                    :repo_sha => pull_request['head']['sha'],
                    :repo_full_name => pull_request['base']['repo']['full_name'])
                  queue_a_build(build_data)
                  request.respond 200
                end
              else
                request.respond 404, "Path not found"
            end
          end
          else
            request.respond 404, "Method not supported"
        end
      end
    end

    def queue_a_build(build_data)
      @build_queue.push(build_data)

      case build_data.build_type
        when :pull_request
          @gh_client.create_status(
            build_data.repo_full_name, build_data.repo_sha, 'pending',
            { :description => "This build is in the queue" })
          info "Pull request build queued"
        when :internal
          info "Internal build queued"
        when :external
          info "External build queued"
      end

      if @build_timer.nil?
        @build_timer = every(5) { on_build_interval }
        info "Build timer started"
      end
    end

    def on_build_interval
      if @active_build.nil?
        if @build_queue.length > 0
          build_data = @build_queue.pop()
          @active_build = build_data
          # TODO: Add timing information into the build_data
          if build_data.build_type == :pull_request
            @gh_client.create_status(
              build_data.repo_full_name, build_data.repo_sha, 'pending',
              { :description => "This build has started" })
          end
          Celluloid::Actor[:builder].async.start_build(build_data)
        elsif @done_queue.length > 0
          # TODO: Should pop everything in the done queue
          build_data = @done_queue.pop
          term_msg = (build_data.termination_type == :killed ? "was stopped" : "completed")
          if build_data.build_type == :pull_request
            description = "The buddy build #{term_msg}"
            if build_data.termination_type == :exited
              if build_data.exit_code != 0
                description += " with errors (exit code #{build_data.exit_code})"
              else
                description += " successfully"
              end
            end
            @gh_client.create_status(
              build_data.repo_full_name, build_data.repo_sha,
              build_data.termination_type == :killed ? 'failure' : build_data.exit_code != 0 ? 'error' : 'success',
              { :description => description })
            info "Pull request build #{term_msg}"
          else
            case build_data.build_type
              when :internal
                message = "An internal build of the `master` branch #{term_msg}."
                info "Internal build #{term_msg}"
              when :external
                message = "An external build of the `#{build_data.build_version}` branch #{term_msg}."
                info "External build #{term_msg}"
            end
            @rt_client.message(channel: @notify_slack_channel, text: message)
          end
        else
          @build_timer.cancel
          @build_timer = nil
          info "Build timer stopped"
        end
      else
        # TODO: Make sure that the build has not run too long and kill if necessary
      end
    end

    def on_build_completed(build_data)
      @active_build = nil
      @done_queue.push(build_data)
    end

    def verify_signature(payload_body, gh_signature)
      signature = 'sha1=' + OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha1'), Config.github_webhook_secret_token, payload_body)
      Rack::Utils.secure_compare(signature, gh_signature)
    end
  end
end
