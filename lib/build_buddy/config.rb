module BuildBuddy
  module Config
    extend self

    ATTRS = [
      :github_webhook_port,
      :github_webhook_secret_token,
      :github_webhook_repo_full_name,
      :github_api_token,
      :slack_api_token,
      :slack_build_channel,
      :slack_pr_channel,
      :slack_builders,
      :build_output_dir,
      :num_saved_build_outputs,
      :pull_request_build_script,
      :branch_build_script,
      :pull_request_root_dir,
      :branch_root_dir,
      :allowed_build_branches,
      :kill_build_after_mins,
      :server_base_uri,
      :mongo_uri,
    ]
    attr_accessor(*ATTRS)
  end

  class << self
    def configure
      config.github_webhook_port = 4567
      config.kill_build_after_mins = 30
      config.mongo_uri = 'mongodb://localhost:27017/build-buddy'
      config.num_saved_build_outputs = 30
      block_given? ? yield(Config) : Config
      config.build_output_dir = File.expand_path(Config.build_output_dir.gsub(/\$(\w+)/) { ENV[$1] })
      Config::ATTRS.map {|attr| ('@' + attr.to_s).to_sym }.each {|var|
        if config.instance_variable_get(var).nil?
          raise "Config value '#{var.to_s.delete('@')}' not set"
        end
      }
    end

    def config
      Config
    end
  end
end
