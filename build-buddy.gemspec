# coding: utf-8

Gem::Specification.new do |s|
  s.name = 'build-buddy'
  s.version = "1.14.7"
  s.summary = %q{An automated build buddy}
  s.description = %q{A build buddy bot with GitHub and Slack integration.}
  s.authors = ["John Lyon-smith"]
  s.email = "john@jamoki.com"
  s.platform = Gem::Platform::RUBY
  s.license = "MIT"
  s.homepage = 'https://github.com/jlyonsmith/build-buddy'
  s.require_paths = ['lib']
  s.required_ruby_version = '~> 2.2'
  s.files = `git ls-files -- lib/*`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.add_runtime_dependency 'timers', ['~> 4.1']
  s.add_runtime_dependency 'celluloid', ['~> 0.17']
  s.add_runtime_dependency 'methadone', ['~> 1.9']
  s.add_runtime_dependency 'slack-ruby-client', ['~> 0.7']
  s.add_runtime_dependency 'json', ['~> 1.8']
  s.add_runtime_dependency 'http', ['~> 1.0']
  s.add_runtime_dependency 'reel', ['~> 0.6']
  s.add_runtime_dependency 'octokit', ['~> 4.2']
  s.add_runtime_dependency 'rack', ['~>1.6']
  s.add_runtime_dependency 'mongo', ['~>2.2']
  s.add_runtime_dependency 'gruff', ['~>0.7']
  s.add_development_dependency 'code-tools', ['~> 5.0']
end
