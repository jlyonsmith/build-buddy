Gem::Specification.new do |s|
  s.name = 'build-buddy'
  s.version = '1.0.0'
  s.date = '2016-01-13'
  s.summary = "Build buddy"
  s.description = "Build buddy bot with GitHub and Slack integration."
  s.authors = ["John Lyon-smith"]
  s.email = "john@jamoki.com"
  s.platform = Gem::Platform::RUBY
  s.files = [
    "lib/build_buddy.rb",
    "lib/build_buddy/server.rb",
    "lib/build_buddy/builder.rb",
    "lib/build_buddy/watcher.rb"]
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.homepage = 'http://rubygems.org/gems/build-buddy'
  s.licenses  = ['MIT']
  s.require_paths = ['lib']
  s.required_ruby_version = '~> 2.2.2'
  s.add_runtime_dependency 'celluloid', ['~> 0.17.2']
  s.add_runtime_dependency 'celluloid-supervision', ['~> 0.20.5']
  s.add_runtime_dependency 'methadone', ['~> 1.9']
  s.add_runtime_dependency 'slack-ruby-client', ['~> 0.5.3']
  s.add_runtime_dependency 'json', ['~> 1.8']
  s.add_runtime_dependency 'http', ['~> 1.0']
  s.add_runtime_dependency 'reel', ['~> 0.6.0.pre3']
  s.add_runtime_dependency 'octokit', ['~> 4.2']
  s.add_runtime_dependency 'rack', ['~>1.6']
  s.add_development_dependency 'code-tools', ['~> 5.0.0']
end
