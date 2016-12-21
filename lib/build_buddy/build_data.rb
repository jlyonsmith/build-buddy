require 'thread'

module BuildBuddy
  @@bb_id = 100
  @@bb_id_mutex = Mutex.new

  def self.bb_id
    @@bb_id
  end

  def self.bb_id=(bb_id)
    @@bb_id = bb_id
  end

  def self.bb_id_mutex
    @@bb_id_mutex
  end

  class BuildData
    attr_accessor :_id # Mongo ID
    attr_accessor :bb_id # Build Buddy id
    attr_accessor :create_time
    attr_accessor :type # one of :master, :release or :pull_request
    attr_accessor :repo_full_name
    attr_accessor :branch
    attr_accessor :pull_request
    attr_accessor :pull_request_title
    attr_accessor :repo_sha
    attr_accessor :termination_type # :killed or :exited
    attr_accessor :started_by
    attr_accessor :stopped_by
    attr_accessor :exit_code
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :flags
    attr_accessor :metrics

    GITHUB_URL = "https://github.com"

    def initialize(args)
      args.each do |key, value|
        begin
          self.method((key.to_s + '=').to_sym).call(value)
        rescue NameError
          # Ignore fields in the database we don't understand
        end
      end

      BuildBuddy::bb_id_mutex.synchronize {
        bb_id = BuildBuddy::bb_id
        @bb_id = 'BB-' + bb_id.to_s
        BuildBuddy::bb_id = bb_id + 1
      }
      @create_time = Time.now.utc
    end

    def to_h
      hash = {}
      instance_variables.each {|var| hash[var.to_s.delete("@").to_sym] = instance_variable_get(var) }
      hash
    end

    def server_log_uri
      BuildData.server_log_uri(@_id)
    end

    def self.server_log_uri(id)
      Config.server_base_uri + '/build/' + id.to_s + '/log.html'
    end

    def self.server_report_uri(id)
      Config.server_base_uri + '/build/' + id.to_s + '/report.html'
    end

    def status_verb
      if @termination_type == :killed
        'stopped'
      else
        @exit_code != 0 ? 'failed' : 'succeeded'
      end
    end

    def url_and_branch_name
      if @type == :branch
        branch_name = "#{@repo_full_name}/#{@branch}"
        url = "#{GITHUB_URL}/#{@repo_full_name}/tree/#{@branch}"
      else
        branch_name = "#{@repo_full_name}/pr/#{@pull_request}"
        url = "#{GITHUB_URL}/#{@repo_full_name}/pull/#{@pull_request}"
      end
      [url, branch_name]
    end

    def run_time
      end_time = @end_time.nil? ? Time.now.utc : @end_time
      start_time = @start_time.nil? ? end_time : @start_time
      Time.at(end_time - start_time).utc.strftime('%H:%M:%S.%L')
    end
  end
end
