require 'celluloid'
require 'ostruct'
require_relative './watcher.rb'
require_relative './config.rb'

module BuildBuddy
  class Builder
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize
      @pid = nil
      @watcher = nil
    end

    def start_build(build_data)
      @build_data = build_data
      repo_parts = build_data.repo_full_name.split('/')
      # TODO: Instead of blocking on the build, start a timer to watch the pid.
      # TODO: Respond to request to kill the build.
      # TODO: Kill the build pid after a certain amount of time has elapsed and report.
      command = "bash "
      env = {
          "GIT_REPO_OWNER" => repo_parts[0],
          "GIT_REPO_NAME" => repo_parts[1]
      }

      case build_data.build_type
        when :pull_request
          env["GIT_PULL_REQUEST"] = build_data.pull_request.to_s
          command += Config.pull_request_build_script
        when :internal
          command += Config.internal_build_script
        when :external
          env["GIT_BRANCH"] = build_data.build_version
          command += Config.external_build_script
        else
          raise "Unknown build type"
      end

      # TODO: Create a log name that is unique
      command += " >build.log 2>&1"

      @pid = Process.spawn(env, command)
      info "Running '#{command}' (process #{@pid})"

      if @watcher
        @watcher.terminate
      end

      @watcher = Watcher.new(@pid)
      @watcher.async.watch_pid
    end

    def process_done(status)
      @build_data.termination_type = (status.signaled? ? :killed : :exited)
      @build_data.exit_code = (status.exited? ? status.exitstatus : -1)
      info "Process #{status.pid} #{@build_data.termination_type == :killed ? 'was terminated' : "exited (#{@build_data.exit_code})"}"
      Celluloid::Actor[:server].async.on_build_completed(@build_data)
      @watcher.terminate
      @watcher = nil
    end

    def stop_build
      if @pid
        info "Killing pid #{@pid}"
        Process.kill(:SIGTERM, @pid)
        # TODO: If that doesn't work, try harder with an SIGABORT
      end
    end
  end
end
