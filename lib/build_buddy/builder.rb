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
      @metrics_file_name = nil
      @build_output_dir = nil
      @log_file_name = nil
    end

    def start_build(build_data)
      def expand_vars(s)
        s.gsub(/\$([a-zA-Z_]+[a-zA-Z0-9_]*)|\$\{(.+)\}/) { ENV[$1||$2] }
      end

      @build_data = build_data
      @build_output_dir = File.join(Config.build_output_dir, @build_data._id.to_s)
      @metrics_file_name = File.join(@build_output_dir, 'metrics.yaml')
      @log_file_name = File.join(@build_output_dir, "log.txt")

      FileUtils.mkdir(@build_output_dir)
      File.new(@metrics_file_name, 'w').close

      repo_parts = @build_data.repo_full_name.split('/')
      git_repo_owner = repo_parts[0]
      git_repo_name = repo_parts[1]
      env = {}
      build_script = %q(#!/bin/bash

if [[ -z "$BB_GIT_REPO_OWNER" || -z "$BB_GIT_REPO_NAME" || -z "$BB_BUILD_SCRIPT" ]]; then
  echo Must set BB_GIT_REPO_OWNER, BB_GIT_REPO_NAME, BB_GIT_PULL_REQUEST and BB_BUILD_SCRIPT before calling
  exit 1
fi
)

      case build_data.type
      when :pull_request
          build_script += %q(
if [[ -z "$BB_GIT_PULL_REQUEST" ]]; then
  echo Must set BB_GIT_PULL_REQUEST before calling
fi
)
      when :branch
        build_script += %q(
if [[ -z "$BB_GIT_BRANCH" ]]; then
  echo Must set BB_GIT_BRANCH before calling
fi
)
      else
        raise "Unknown build type"
      end

      build_script += %q(
if [[ -d ${BB_GIT_REPO_NAME} ]]; then
  echo WARNING: Deleting old clone directory $(pwd)/${BB_GIT_REPO_NAME}
  rm -rf ${BB_GIT_REPO_NAME}
fi

echo Pulling sources to $(pwd)/${BB_GIT_REPO_NAME}
if ! git clone git@github.com:${BB_GIT_REPO_OWNER}/${BB_GIT_REPO_NAME}.git ${BB_GIT_REPO_NAME}; then
  echo ERROR: Unable to clone repository
  exit 1
fi

cd ${BB_GIT_REPO_NAME}
)

      build_root_dir = nil

      case build_data.type
      when :pull_request
        build_root_dir = expand_vars(Config.pull_request_root_dir)
        env.merge!({
          "BB_GIT_PULL_REQUEST" => build_data.pull_request.to_s,
          "BB_BUILD_SCRIPT" => Config.pull_request_build_script
        })
        # See https://gist.github.com/piscisaureus/3342247
        build_script += %q(
echo Switching to pr/${BB_GIT_PULL_REQUEST} branch
git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
git fetch -q origin
git checkout pr/$BB_GIT_PULL_REQUEST
)
      when :branch
        build_root_dir = expand_vars(Config.branch_root_dir)
        env.merge!({
          "BB_GIT_BRANCH" => build_data.branch.to_s,
          "BB_BUILD_SCRIPT" => Config.branch_build_script
        })
        build_script += %q(
echo Switching to ${BB_GIT_BRANCH} branch
git checkout ${BB_GIT_BRANCH}
)
      end

      build_script += %q(
source ${BB_BUILD_SCRIPT}
)
      env.merge!({
          "BB_GIT_REPO_OWNER" => git_repo_owner,
          "BB_GIT_REPO_NAME" => git_repo_name,
          "BB_METRICS_DATA_FILE" => @metrics_file_name,
          "BB_BUILD_OUTPUT_DIR" => @build_output_dir,
          "BB_MONGO_URI" => Config.mongo_uri,
          "RBENV_DIR" => nil,
          "RBENV_VERSION" => nil,
          "RBENV_HOOK_PATH" => nil,
          "RBENV_ROOT" => nil,
          "PATH" => ENV['PATH'].split(':').select { |v| !v.match(/\.rbenv\/versions|Cellar\/rbenv/) }.join(':'),
      })

      unless build_data.flags.nil?
        build_data.flags.each do |flag|
          env["BB_BUILD_FLAG_#{flag.to_s.upcase}"] = '1'
        end
      end

      @build_data.start_time = Time.now.utc

      # Ensure build root and git user directory exists
      clone_dir = File.join(build_root_dir, git_repo_owner)
      FileUtils.mkdir_p(clone_dir)

      # Write the bootstrapping build script to it
      script_filename = File.join(clone_dir, "build-buddy-bootstrap.sh")
      File.write(script_filename, build_script)

      # Notify GitHub that build has started
      if @build_data.type == :pull_request
        Celluloid::Actor[:gitter].async.set_status(
            build_data.repo_full_name, build_data.repo_sha, :pending, "Build has started",
            build_data.server_log_uri)
      end

      # Run the build script
      Bundler.with_clean_env do
        @pid = Process.spawn(env, "bash #{script_filename}", :pgroup => true, :chdir => clone_dir, [:out, :err] => @log_file_name)
        @gid = Process.getpgid(@pid)
      end
      info "Running build script (pid #{@pid}, gid #{@gid}) : Log #{@log_file_name}"

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
      metrics = {}

      if File.exist?(@metrics_file_name)
        metrics_yaml = File.read(@metrics_file_name)
        begin
          metrics = Psych.load_stream(metrics_yaml).reduce({}, :merge)
        rescue Psych::SyntaxError => ex
          error "There was a problem collecting build metrics: #{ex.message}\n#{metrics_yaml}"
        end
      end

      @build_data.metrics = metrics

      # Send status to GitHub if pull request
      if @build_data.type == :pull_request
        git_state = (@build_data.termination_type == :killed ? :failure : @build_data.exit_code != 0 ? :error : :success)
        status_verb = @build_data.status_verb
        Celluloid::Actor[:gitter].async.set_status(
            @build_data.repo_full_name, @build_data.repo_sha, git_state, "Build #{status_verb}",
            @build_data.server_log_uri)
      end

      # Create a log.html file
      log_contents = ''
      File.open(@log_file_name) do |io|
        log_contents = io.read
      end
      html = %Q(
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Build Log</title>
  <meta name="description" content="Build Log">
  <style>
    body {
      background-color: black;
      color: #f0f0f0;
    }
    pre {
      font-family: "Menlo", "Courier New";
      font-size: 10pt;
    }
  </style>
</head>

<body>
  <pre>
#{log_contents}
  </pre>
</body>
</html>
)
      File.open(File.join(@build_output_dir, "log.html"), 'w') { |f| f.write(html)}

      # Log the build completion and clean-up
      info "Process #{status.pid} #{@build_data.termination_type == :killed ? 'was terminated' : "exited (#{@build_data.exit_code})"}"
      Celluloid::Actor[:scheduler].async.on_build_completed(@build_data)
      @watcher.terminate
      @watcher = nil

      # Delete older log directories
      log_dir_names = Dir.entries(Config.build_output_dir)
        .select {|fn| fn.match(/[0-9a-z]{24}$/)}
        .sort_by! {|fn| File.mtime(File.join(Config.build_output_dir, fn))}
      while log_dir_names.count > Config.num_saved_build_outputs
        dir_name = log_dir_names.shift
        FileUtils.rm_rf(File.join(Config.build_output_dir, dir_name))
        info "Removing oldest log directory #{dir_name}"
      end
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
