module BuildBuddy
  module Config
    extend self

    attr_accessor :github_webhook_secret_token
    attr_accessor :github_webhook_repo_full_name
    attr_accessor :github_api_token
    attr_accessor :slack_api_token
    attr_accessor :slack_build_channel
    attr_accessor :xcode_workspace
    attr_accessor :xcode_test_scheme
    attr_accessor :build_log_dir
    attr_accessor :pull_request_build_script
    attr_accessor :master_build_script
    attr_accessor :release_build_script
  end

  class << self
    def configure
      block_given? ? yield(Config) : Config
    end

    def config
      Config
    end
  end
end
