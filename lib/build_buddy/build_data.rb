module BuildBuddy
  class BuildData
    attr_accessor :_id # Mongo ID
    attr_accessor :type # one of :master, :release or :pull_request
    attr_accessor :repo_full_name
    attr_accessor :branch
    attr_accessor :pull_request
    attr_accessor :repo_sha
    attr_accessor :termination_type # :killed or :exited
    attr_accessor :started_by
    attr_accessor :stopped_by
    attr_accessor :exit_code
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :flags
    attr_accessor :metrics

    def initialize(args)
      args.each do |key, value|
        begin
          self.method((key.to_s + '=').to_sym).call(value)
        rescue NameError
          # Ignore fields in the database we don't understand
        end
      end

      # Set the id here so that we can use it to refer to this build_data in queue
      @_id = BSON::ObjectId.new
    end

    def to_h
      hash = {}
      instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
      hash
    end

    def server_log_uri
      Config.server_base_uri + '/log/' + @_id.to_s
    end

    def status_verb
      if @termination_type == :killed
        'was stopped'
      else
        @exit_code != 0 ? 'failed' : 'succeeded'
      end
    end

    def pull_request_uri
      "https://github.com/#{@repo_full_name}/pull/#{@pull_request}"
    end

    def log_file_name
      return nil if @start_time.nil?
      File.join(Config.build_log_dir, "#{@start_time.strftime('%Y%m%d-%H%M%S')}.log")
    end
  end
end
