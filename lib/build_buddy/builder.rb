require 'rubygems'
require 'bundler'
require 'celluloid'
require 'psych'
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
      @metrics_tempfile = nil
      @variables_regex = /\$([a-zA-Z_]+[a-zA-Z0-9_]*)|\$\{(.+)\}/
    end

    def expand_vars(s)
      s.gsub(@variables_regex) { self[$1||$2] }
    end

    def start_build(build_data)
      @build_data = build_data
      @metrics_tempfile = Tempfile.new('build-metrics')
      @metrics_tempfile.close()

      repo_parts = build_data.repo_full_name.split('/')

      case build_data.type
      when :pull_request
        build_root_dir = Config.pull_request_root_dir
        env["GIT_PULL_REQUEST"] = build_data.pull_request.to_s
        env["BUILD_ROOT_DIR"] = expand_vars(build_root_dir)
        env["BUILD_SCRIPT"] = Config.pull_request_build_script
        script += %q(
echo Switching to ${GIT_PULL_REQUEST} branch
git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
git fetch -q origin
git checkout pr/$GIT_PULL_REQUEST
)
      when :branch
        build_root_dir = Config.branch_root_dir
        env["GIT_BRANCH"] = 'master'
        env["BUILD_ROOT_DIR"] = build_root_dir
        env["BUILD_SCRIPT"] = Config.branch_build_script
        script += %q(
echo Switching to ${GIT_BRANCH} branch
git checkout ${GIT_BRANCH}
)
      else
        raise "Unknown build type"
      end

      env.merge({
          "GIT_REPO_OWNER" => repo_parts[0],
          "GIT_REPO_NAME" => repo_parts[1],
          "METRICS_DATA_FILE" => @metrics_tempfile.path,
          "RBENV_DIR" => nil,
          "RBENV_VERSION" => nil,
          "RBENV_HOOK_PATH" => nil,
          "RBENV_ROOT" => nil,
          "PATH" => ENV['PATH'].split(':').select { |v| !v.match(/\.rbenv\/versions|Cellar\/rbenv/) }.join(':'),
      })

      script = %q(#!/bin/bash
if [[ -d ${GIT_REPO_NAME} ]]; then
  echo Deleting old clone directory $(pwd)/${GIT_REPO_NAME}
  rm -rf ${GIT_REPO_NAME}
fi
echo Pulling sources to $(pwd)/${GIT_REPO_NAME}
git clone git@github.com:${GIT_REPO_OWNER}/${GIT_REPO_NAME}.git ${GIT_REPO_NAME}
cd ${GIT_REPO_NAME}
source ${BUILD_SCRIPT}
)

      unless build_data.flags.nil?
        build_data.flags.each do |flag|
         env["BUILD_FLAG_#{flag.to_s.upcase}"] = '1'
        end
      end

      @build_data.start_time = Time.now.utc
      log_filename = File.join(Config.build_log_dir,
        "build_#{build_data.type.to_s}_#{build_data.start_time.strftime('%Y%m%d_%H%M%S')}.log")
      @build_data.log_filename = log_filename

      # Ensure build root directory exists
      File.mkdir_p(build_root_dir)

      # Write the bootstrapping build script to it
      script_filename = File.join(build_root_dir, repo_parts[0], repo_parts[1], "build-buddy-bootstrap.sh")
      File.write(script_filename, script)

      # Run the build script
      Bundler.with_clean_env do
        @pid = Process.spawn(env, "bash #{script_filename}", :pgroup => true, :chdir => build_root_dir, [:out, :err] => log_filename)
        @gid = Process.getpgid(@pid)
      end
      info "Running #{File.basename(command)} (pid #{@pid}, gid #{@gid}) : Log #{log_filename}"

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

      # Collect any data written to the build metrics YAML file
      begin
        metrics = Psych.load_stream(File.read(@metrics_tempfile.path)).reduce({}, :merge)
      rescue Psych::SyntaxError => ex
        error "There was a problem collecting build metrics: #{ex.message}"
      end
      if !metrics
        metrics = {}
      end
      @build_data.metrics = metrics

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
