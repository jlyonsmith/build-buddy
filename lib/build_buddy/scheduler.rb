require 'rubygems'
require 'bundler'
require 'celluloid'
require 'timers'
require_relative './config.rb'

module BuildBuddy
  class Scheduler
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize()
      @build_queue = []
      @done_queue = []
      @build_timer = nil
      @active_build = nil
    end

    def queue_a_build(build_data)
      case build_data.type
      when :pull_request
        existing_bb_id = find_bb_id_for_pr(build_data.pull_request)

        Celluloid::Actor[:gitter].async.set_status(
            build_data.repo_full_name, build_data.repo_sha, :pending, "Build is queued",
            build_data.server_log_uri)
        info "Pull request build queued"

        unless existing_bb_id.nil?
          info "Stopping existing build #{existing_bb_id} for this PR"
          stop_build(existing_bb_id, 'github')
        end
      when :branch
        info "'#{build_data.branch}' branch build queued"
      end

      @build_queue.unshift(build_data)

      if @build_timer.nil?
        @build_timer = every(5) { on_build_interval }
        info "Build timer started"
      end
    end

    def find_bb_id_for_pr(pull_request)
      if @active_build and @active_build.pull_request == pull_request
        return @active_build.bb_id
      end

      build_data = @build_queue.find { |build_data| build_data.pull_request == pull_request}

      if build_data.nil?
        nil
      else
        build_data.bb_id
      end
    end

    def queue_length
      @build_queue.length
    end

    def active_build
      @active_build
    end

    def stop_build(bb_id, slack_user_name)
      # Centralize stopping builds here
      if @active_build != nil and @active_build.bb_id == bb_id
        @active_build.stopped_by = slack_user_name
        Celluloid::Actor[:builder].async.stop_build
        # Build data will be recorded when the build stops
        return :active
      end

      # Look for the build in the queue
      i = @build_queue.find_index { |build_data| build_data.bb_id == bb_id}
      if i != nil
        build_data = @build_queue[i]
        @build_queue.delete_at(i)
        return :in_queue
      end

      return :not_found
    end

    def on_build_interval
      if @active_build.nil?
        # No active build so...
        if @done_queue.length > 0  # First, send any completed build statuses
          build_data = @done_queue.pop
          Celluloid::Actor[:slacker].async.notify_channel(build_data)
          Celluloid::Actor[:recorder].async.update_build_data(build_data)
        elsif @build_queue.length > 0  # Then, check if there are any builds waiting to go
          build_data = @build_queue.pop()
          @active_build = build_data
          Celluloid::Actor[:recorder].async.record_build_data_and_start_build(build_data)
        else # Otherwise, stop the timer until we get a build queued.
          @build_timer.cancel
          @build_timer = nil
          info "Build timer stopped"
          # Now we won't get any more build intervals
        end
      else
        # Make sure that the build has not run too long and kill if necessary
        start_time = @active_build.start_time
        if !start_time.nil? and Time.now.utc - start_time > Config.kill_build_after_mins * 60
          Celluloid::Actor[:builder].async.stop_build
        end
      end
    end

    def on_build_completed(build_data)
      @active_build = nil
      @done_queue.unshift(build_data)
    end

    def get_build_queue
      @build_queue.clone
    end
  end
end
