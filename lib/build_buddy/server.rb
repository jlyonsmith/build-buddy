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
      info "Web server listening on port #{Config.github_webhook_port}"
    end

    def on_connection(connection)
      connection.each_request do |request|
        case request.path
        when '/webhook'
          case request.method
          when 'POST'
            case request.headers["X-GitHub-Event"]
            when 'pull_request'
              payload_text = request.body.to_s
              if !verify_signature(payload_text, request.headers["X-Hub-Signature"])
                request.respond 500, "Signatures didn't match!"
              else
                payload = JSON.parse(payload_text)
                action = payload['action']
                pull_request = payload['pull_request']

                info "Got pull request '#{action}' from #{forwarded_for(request)}"
                case action
                when 'opened', 'reopened', 'synchronize'
                  build_data = BuildData.new(
                      :type => :pull_request,
                      :pull_request => pull_request['number'],
                      :flags => {},
                      :repo_sha => pull_request['head']['sha'],
                      :repo_full_name => pull_request['base']['repo']['full_name'],
                      :started_by => 'github')
                  info "Got #{action} pull request #{build_data.pull_request} from GitHub"
                  Celluloid::Actor[:scheduler].queue_a_build(build_data)
                  request.respond 200, "Building"
                else
                  request.respond 200, "Ignoring"
                end
              end
            when 'ping'
              info "Got pinged from #{forwarded_for(request)}"
              request.respond 200, "Running"
            else
              request.respond 404, "Event not supported"
            end
          else
            request.respond 404, "Method not supported"
          end
        when /^\/build\/([0-9abcdef]{24})\/(log\.html|report\.html|[a-z_]+\.png)$/
          if request.method != 'GET'
            request.respond 404, "Method not supported"
            return
          end

          build_id = $1
          resource_name = $2
          if build_id.nil? or resource_name.nil?
            request.respond 404, "Not found"
            return
          end

          resource_file_name = File.join(Config.build_output_dir, build_id, resource_name)
          if !File.exist?(resource_file_name)
            request.respond 404, "Not found"
            return
          end

          if resource_name.end_with?('.html')
            request.respond Reel::Response.new(200, { 'content-type' => 'text/html'}, File.open(resource_file_name, 'r'))
          else
            request.respond Reel::Response.new(200, { 'content-type' => 'image/png'}, File.open(resource_file_name, 'rb'))
          end
        else
          request.respond 404, "Not found"
        end
      end
    end

    def forwarded_for(request)
      addr = request.headers["X-Forwarded-For"]

      if addr.start_with?("192.30.252")
        return "github.com (#{addr})"
      else
        return "unknown (#{addr})"
      end
    end

    def verify_signature(payload_body, gh_signature)
      signature = 'sha1=' + OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new('sha1'), Config.github_webhook_secret_token, payload_body)
      Rack::Utils.secure_compare(signature, gh_signature)
    end
  end
end
