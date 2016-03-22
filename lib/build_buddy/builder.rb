require 'rubygems'
require 'bundler'
require 'celluloid'
require_relative './watcher.rb'
require_relative './config.rb'

module BuildBuddy
  class Builder
    include Celluloid
    include Celluloid::Internals::Logger

    def initialize
      @pid = nil
      @gid = nil
      @watcher = nil
      @exit_data_tempfile = nil
    end

    def start_build(build_data)
      @build_data = build_data
      @exit_data_tempfile = Tempfile.new('build-results')
      @exit_data_tempfile.close()

      repo_parts = build_data.repo_full_name.split('/')
      command = "bash "
      env = {
          "GIT_REPO_OWNER" => repo_parts[0],
          "GIT_REPO_NAME" => repo_parts[1],
          "EXIT_DATA_FILE" => @exit_data_tempfile.path,
          "RBENV_DIR" => nil,
          "RBENV_VERSION" => nil,
          "RBENV_HOOK_PATH" => nil,
          "RBENV_ROOT" => nil,
          "PATH" => ENV['PATH'].split(':').select { |v| !v.match(/\.rbenv\/versions|Cellar\/rbenv/) }.join(':')
      }

      case build_data.build_type
        when :pull_request
          env["GIT_PULL_REQUEST"] = build_data.pull_request.to_s
          command += Config.pull_request_build_script
        when :master
          command += Config.master_build_script
        when :release
          env["GIT_BRANCH"] = build_data.build_version
          command += Config.release_build_script
        else
          raise "Unknown build type"
      end

      @build_data.start_time = Time.now.utc
      build_log_filename = File.join(Config.build_log_dir,
        "build_#{build_data.build_type.to_s}_#{build_data.start_time.strftime('%Y%m%d_%H%M%S')}.log")
      @build_data.build_log_filename = build_log_filename

      Bundler.with_clean_env do
        @pid = Process.spawn(env, command, :pgroup => true, [:out, :err] => build_log_filename)
        @gid = Process.getpgid(@pid)
      end
      info "Running #{File.basename(command)} (pid #{@pid}, gid #{@gid}) : Log #{build_log_filename}"

      if @watcher
        @watcher.terminate
      end

      @watcher = Watcher.new(@pid)
      @watcher.async.watch_pid
    end

    def process_done(status)
      @build_data.end_time = Time.now.utc
      @build_data.termination_type = (status.signaled? ? :killed : :exited)
      @build_data.exit_code = (status.exited? ? status.exitstatus : -1)

      # Collect any information written to the build results file
      exit_data = {}
      File.open(@exit_data_tempfile.path) do |io|
        text = io.read()
        if text.length >= 2
          exit_data = JSON.parse(text)
        end
      end
      @build_data.exit_data = exit_data

      info "Process #{status.pid} #{@build_data.termination_type == :killed ? 'was terminated' : "exited (#{@build_data.exit_code})"}"
      Celluloid::Actor[:scheduler].async.on_build_completed(@build_data)
      @watcher.terminate
      @watcher = nil
    end

    def stop_build
      if @gid
        info "Killing gid #{@gid}"
        Process.kill(:SIGABRT, -@gid)
        @gid = nil
      end
    end
  end
end
