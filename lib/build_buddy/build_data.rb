module BuildBuddy
  class BuildData
    attr_accessor :_id # Mongo ID
    attr_accessor :type # one of :master, :release or :pull_request
    attr_accessor :repo_full_name
    attr_accessor :branch
    attr_accessor :pull_request
    attr_accessor :repo_full_name
    attr_accessor :repo_sha
    attr_accessor :termination_type # :killed or :exited
    attr_accessor :exit_code
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :log_filename
    attr_accessor :flags # :no_upload, :test_channel
    attr_accessor :metrics

    def initialize(args)
      args.each do |key, value|
        setter = self.method((key.to_s + '=').to_sym)

        unless setter.nil?
          setter.call(value)
        end
      end
    end

    def to_h
      hash = {}
      instance_variables.each {|var| hash[var.to_s.delete("@")] = instance_variable_get(var) }
      hash
    end
  end
end
