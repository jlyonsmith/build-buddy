require 'rubygems'
require 'celluloid/current'
require 'reel'
require 'json'
require 'rack'
require_relative './builder.rb'

module BuildBuddy
  class Server < Reel::Server::HTTP
    include Celluloid::Internals::Logger

    def initialize()
      super("127.0.0.1", Config.github_webhook_port, &method(:on_connection))
      info "Listening on port #{Config.github_webhook_port}"
    end

    def on_connection(connection)
      connection.each_request do |request|
        case request.method
        when 'POST'
          case request.path
          when Config.github_webhook_path
            case request.headers["X-GitHub-Event"]
            when 'pull_request'
              payload_text = request.body.to_s
              if !verify_signature(payload_text, request.headers["X-Hub-Signature"])
                request.respond 500, "Signatures didn't match!"
              else
                payload = JSON.parse(payload_text)
                pull_request = payload['pull_request']
                build_data = BuildData.new(:pull_request,
                  :pull_request => pull_request['number'],
                  :repo_sha => pull_request['head']['sha'],
                  :repo_full_name => pull_request['base']['repo']['full_name'])
                info "Got pull request #{build_data.pull_request} from GitHub"
                Celluloid::Actor[:scheduler].queue_a_build(build_data)
                request.respond 200
              end
            when 'ping'
              request.respond 200, "Running"
            else
              request.respond 404, "Path not found"
            end
          else
           request.respond 404, "Path not found"
          end
        # TODO: Implement basic access authentication from config file
        # TODO: Implement getting the log file
        else
          request.respond 404, "Method not supported"
        end
      end
    end

    def verify_signature(payload_body, gh_signature)
      signature = 'sha1=' + OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha1'), Config.github_webhook_secret_token, payload_body)
      Rack::Utils.secure_compare(signature, gh_signature)
    end
  end
end
