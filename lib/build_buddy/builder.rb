require 'rubygems'
require 'bundler'
require 'celluloid'
require 'psych'
require 'fileutils'
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
    end

    def start_build(build_data)
      def expand_vars(s)
        s.gsub(/\$([a-zA-Z_]+[a-zA-Z0-9_]*)|\$\{(.+)\}/) { ENV[$1||$2] }
      end

      @build_data = build_data
      @metrics_tempfile = Tempfile.new('build-metrics')
      @metrics_tempfile.close()

      repo_parts = build_data.repo_full_name.split('/')
      git_repo_owner = repo_parts[0]
      git_repo_name = repo_parts[1]
      env = {}
      build_script = %q(#!/bin/bash

if [[ -z "$GIT_REPO_OWNER" || -z "$GIT_REPO_NAME" || -z "$BUILD_SCRIPT" ]]; then
  echo Must set GIT_REPO_OWNER, GIT_REPO_NAME, GIT_PULL_REQUEST and BUILD_SCRIPT before calling
  exit 1
fi
)

      case build_data.type
      when :pull_request
          build_script += %q(
if [[ -z "$GIT_PULL_REQUEST" ]]; then
  echo Must set GIT_PULL_REQUEST before calling
fi
)
      when :branch
        build_script += %q(
if [[ -z "$GIT_BRANCH" ]]; then
  echo Must set GIT_BRANCH before calling
fi
)
      else
        raise "Unknown build type"
      end

      build_script += %q(
if [[ -d ${GIT_REPO_NAME} ]]; then
  echo WARNING: Deleting old clone directory $(pwd)/${GIT_REPO_NAME}
  rm -rf ${GIT_REPO_NAME}
fi

echo Pulling sources to $(pwd)/${GIT_REPO_NAME}
if ! git clone git@github.com:${GIT_REPO_OWNER}/${GIT_REPO_NAME}.git ${GIT_REPO_NAME}; then
  echo ERROR: Unable to clone repository
  exit 1
fi

cd ${GIT_REPO_NAME}
)

      case build_data.type
      when :pull_request
        build_root_dir = expand_vars(Config.pull_request_root_dir)
        env.merge!({
          "GIT_PULL_REQUEST" => build_data.pull_request.to_s,
          "BUILD_SCRIPT" => Config.pull_request_build_script
        })
        # See https://gist.github.com/piscisaureus/3342247
        build_script += %q(
echo Switching to pr/${GIT_PULL_REQUEST} branch
git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
git fetch -q origin
git checkout pr/$GIT_PULL_REQUEST
)
      when :branch
        build_root_dir = expand_vars(Config.branch_root_dir)
        env.merge!({
          "GIT_BRANCH" => 'master',
          "BUILD_SCRIPT" => Config.branch_build_script
        })
        build_script += %q(
echo Switching to ${GIT_BRANCH} branch
git checkout ${GIT_BRANCH}
)
      end

      build_script += %q(
source ${BUILD_SCRIPT}
)
      env.merge!({
          "GIT_REPO_OWNER" => git_repo_owner,
          "GIT_REPO_NAME" => git_repo_name,
          "METRICS_DATA_FILE" => @metrics_tempfile.path,
          "RBENV_DIR" => nil,
          "RBENV_VERSION" => nil,
          "RBENV_HOOK_PATH" => nil,
          "RBENV_ROOT" => nil,
          "PATH" => ENV['PATH'].split(':').select { |v| !v.match(/\.rbenv\/versions|Cellar\/rbenv/) }.join(':'),
      })

      unless build_data.flags.nil?
        build_data.flags.each do |flag|
         env["BUILD_FLAG_#{flag.to_s.upcase}"] = '1'
        end
      end

      @build_data.start_time = Time.now.utc
      log_filename = File.join(File.expand_path(Config.build_log_dir),
        "build_#{build_data.type.to_s}_#{build_data.start_time.strftime('%Y%m%d_%H%M%S')}.log")
      @build_data.log_filename = log_filename

      # Ensure build root and git user directory exists
      clone_dir = File.join(build_root_dir, git_repo_owner)
      FileUtils.mkdir_p(clone_dir)

      # Write the bootstrapping build script to it
      script_filename = File.join(clone_dir, "build-buddy-bootstrap.sh")
      File.write(script_filename, build_script)

      # Run the build script
      Bundler.with_clean_env do
        @pid = Process.spawn(env, "bash #{script_filename}", :pgroup => true, :chdir => clone_dir, [:out, :err] => log_filename)
        @gid = Process.getpgid(@pid)
      end
      info "Running build script (pid #{@pid}, gid #{@gid}) : Log #{log_filename}"

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
