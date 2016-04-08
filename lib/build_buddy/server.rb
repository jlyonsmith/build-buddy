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
                pull_request = payload['pull_request']
                pull_request_action = pull_request['action']

                case action
                when 'opened', 'reopened', 'synchronize'
                  build_data = BuildData.new(
                      :type => :pull_request,
                      :pull_request => pull_request['number'],
                      :flags => [],
                      :repo_sha => pull_request['head']['sha'],
                      :repo_full_name => pull_request['base']['repo']['full_name'])
                  info "Got #{action} pull request #{build_data.pull_request} from GitHub"
                  Celluloid::Actor[:scheduler].queue_a_build(build_data)
                  request.respond 200, "Building"
                else
                  request.respond 200, "Ignoring"
                end
              end
            when 'ping'
              request.respond 200, "Running"
            else
              request.respond 404, "Event not supported"
            end
          else
            request.respond 404, "Method not supported"
          end
        when /^\/log\/([0-9a-z]*)$/
          case request.method
          when 'GET'
            build_data = Celluloid::Actor[:recorder].get_build_data($1)
            if build_data.nil? or build_data.log_filename.nil? or !File.exist?(build_data.log_filename)
              sleep 1
              request.respond 404, "Not found"
            end
            log_contents = 'Log file has been deleted.'
            File.open(build_data.log_filename) do |io|
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
            request.respond 200, html
          else
            request.respond 404, "Method not supported"
          end
        else
           request.respond 404, "Path not found"
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
