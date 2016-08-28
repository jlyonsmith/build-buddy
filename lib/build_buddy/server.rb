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
                      :repo_full_name => pull_request['base']['repo']['full_name'])
                  info "Got #{action} pull request #{build_data.pull_request} from GitHub"
                  Celluloid::Actor[:scheduler].queue_a_build(build_data)
                  request.respond 200, "Building"
                  return
                else
                  request.respond 200, "Ignoring"
                  return
                end
              end
            when 'ping'
              info "Got pinged from #{forwarded_for(request)}"
              request.respond 200, "Running"
              return
            else
              request.respond 404, "Event not supported"
              return
            end
          else
            request.respond 404, "Method not supported"
            return
          end
        when /^\/log\/([0-9abcdef]{24})$/
          case request.method
          when 'GET'
            build_data = Celluloid::Actor[:recorder].get_build_data($1)
            if build_data.nil?
              request.respond 404, "Not found"
              return
            end
            log_file_name = build_data.log_file_name
            if log_file_name.nil? or !File.exist?(log_file_name)
              log_contents = 'Log file has been deleted.'
            else
              File.open(log_file_name) do |io|
                log_contents = io.read
              end
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
            return
          else
            request.respond 404, "Method not supported"
            return
          end
        when Regexp.new("^/hud/#{Config.hud_secret_token}/(index\\.html|[a-z_]+\\.png)$")
          if request.method != 'GET'
            request.response 404, "Method not supported"
            return
          end

          if $1 == "index.html"
            html = %q(
<!doctype html>
<html lang="en">
<head>
  <title>Build Metrics</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="http://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.3/css/bootstrap.min.css" integrity="sha384-MIwDKRSSImVFAZCVLtU0LMDdON6KVCrZHyVQQj6e8wIEJkW4tvwqXrbMIya1vriY" crossorigin="anonymous">
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.3/js/bootstrap.min.js" integrity="sha384-ux8v3A6CPtOTqOzMKiuo3d/DomGaaClxFYdCu2HPMBEkf6x2xiDyJ7gkXU0MWwaD" crossorigin="anonymous"></script>
</head>
<body>

<div class="jumbotron text-center">
  <h1>Build Metrics</h1>
  <p>Build server data</p>
</div>

<div class="container-fluid">
  <div class="row">
    <div class="col-sm-4">
      <img class="img-fluid" src="code_coverage.png" alt="Code Coverage">
    </div>
    <div class="col-sm-4">
      <img class="img-fluid" src="build_times.png" alt="Build Times">
    </div>
    <div class="col-sm-4">
      <img class="img-fluid" src="daily_builds.png" alt="Daily Builds">
    </div>
  </div>
  <div class="row">
    <div class="col-sm-4">
      <img class="img-fluid" src="lines_of_code.png" alt="Lines of Code">
    </div>
    <div class="col-sm-4">
      <img class="img-fluid" src="localization_data.png" alt="Localization Data">
    </div>
    <div class="col-sm-4">
      <img class="img-fluid" src="warning_count.png" alt="Warning Count">
    </div>
  </div>
</div>

</body>
</html>
)
            request.respond 200, html
            return
          elsif
            png_file_name = File.join(Config.hud_image_dir, $1)

            if File.exist?(png_file_name)
              request.respond Reel::Response.new(200, {"content-type" => "image/png"}, File.open(png_file_name))
              return
            else
              request.response 404, "Image not found"
              return
            end
          else
            request.response 404, "Path not found"
            return
          end
        else
          request.respond 404, "Path not found"
          return
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
