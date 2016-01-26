# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'build_buddy'

Gem::Specification.new do |s|
  s.name = 'build-buddy'
  s.version = BuildBuddy::VERSION
  s.summary = %q{An automated build buddy}
  s.description = %q{A build buddy bot with GitHub and Slack integration.}
  s.authors = ["John Lyon-smith"]
  s.email = "john@jamoki.com"
  s.platform = Gem::Platform::RUBY
  s.license = "MIT"
  s.homepage = 'http://rubygems.org/gems/build-buddy'
  s.require_paths = ['lib']
  s.required_ruby_version = '~> 2.0'
  s.files = `git ls-files -- lib/*`.split("\n")
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.add_runtime_dependency 'timers', ['~> 4.1']
  s.add_runtime_dependency 'celluloid', ['~> 0.17.2']
  s.add_runtime_dependency 'celluloid-supervision', ['~> 0.20.5']
  s.add_runtime_dependency 'methadone', ['~> 1.9']
  s.add_runtime_dependency 'slack-ruby-client', ['~> 0.5.3']
  s.add_runtime_dependency 'json', ['~> 1.8']
  s.add_runtime_dependency 'http', ['~> 1.0']
  s.add_runtime_dependency 'reel', ['= 0.6.0.pre3'] # Relax this once it's released
  s.add_runtime_dependency 'octokit', ['~> 4.2']
  s.add_runtime_dependency 'rack', ['~>1.6']
  s.add_development_dependency 'code-tools', ['~> 5.0']
end
