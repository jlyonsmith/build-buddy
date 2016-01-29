module BuildBuddy
  class BuildData
    attr_accessor :build_type # one of :master, :release or :pull_request
    attr_accessor :repo_full_name
    attr_accessor :build_version
    attr_accessor :repo_full_name
    attr_accessor :repo_sha
    attr_accessor :termination_type
    attr_accessor :exit_code
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :build_log_filename

    def initialize(build_type, args)
      @build_type = build_type
      @repo_full_name = args[:repo_full_name]
      @repo_sha = args[:repo_sha]
      @build_version = args[:build_version]
    end
  end
end
