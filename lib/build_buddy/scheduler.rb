require 'rubygems'
require 'bundler'
require 'celluloid'
require 'timers'
require_relative './config.rb'

module BuildBuddy
  class Scheduler
    include Celluloid
    include Celluloid::Internals::Logger

    attr_reader :active_build

    def initialize()
      @build_queue = Queue.new
      @done_queue = Queue.new
      @build_timer = nil
    end

    def queue_a_build(build_data)
      @build_queue.push(build_data)

      case build_data.type
        when :pull_request
          Celluloid::Actor[:gitter].async.set_status(
              build_data.repo_full_name, build_data.repo_sha, :pending, "This build is in the queue")
          info "Pull request build queued"
        when :master
          info "`master` branch build queued"
        when :release
          info "Release branch build queued"
      end

      if @build_timer.nil?
        @build_timer = every(5) { on_build_interval }
        info "Build timer started"
      end
    end

    def queue_length
      @build_queue.length
    end

    def stop_build
      # Centralize stopping bulids here in case we allow multiple active builders in future
      unless @active_build.nil?
        Celluloid::Actor[:builder].stop_build
        true
      else
        false
      end
    end

    def on_build_interval
      if @active_build.nil?
        if @build_queue.length > 0
          build_data = @build_queue.pop()
          @active_build = build_data
          Celluloid::Actor[:recorder].async.record_build_data(build_data)
          if build_data.type == :pull_request
            Celluloid::Actor[:gitter].async.set_status(
                build_data.repo_full_name, build_data.repo_sha, :pending, "This build has started")
          end
          Celluloid::Actor[:builder].async.start_build(build_data)
        elsif @done_queue.length > 0
          build_data = @done_queue.pop
          Celluloid::Actor[:slacker].async.notify_channel(build_data)
          Celluloid::Actor[:recorder].async.update_build_data(build_data)
        else
          @build_timer.cancel
          @build_timer = nil
          info "Build timer stopped"
        end
      else
        # Make sure that the build has not run too long and kill if necessary
        start_time = @active_build.start_time
        if !start_time.nil? and Time.now.utc - start_time > Config.kill_build_after_mins * 60
          Celluloid::Actor[:builder].async.stop_build()
        end
      end
    end

    def on_build_completed(build_data)
      @active_build = nil
      @done_queue.push(build_data)
    end
  end
end