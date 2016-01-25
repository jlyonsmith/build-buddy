require 'rubygems'
require 'celluloid'

module BuildBuddy
  class Watcher
    include Celluloid

    def initialize(pid)
      @pid = pid
    end

    def watch_pid
      Process.waitpid2(@pid)
      Celluloid::Actor[:builder].async.process_done($?)
    end
  end
end
