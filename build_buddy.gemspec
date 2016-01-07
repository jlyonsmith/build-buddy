Gem::Specification.new do |s|
  s.name = 'build_buddy'
  s.version = '1.0.0'
  s.date = '2016-01-10'
  s.summary = "Source code tools"
  s.description = "Tools for source code maintenance, including version stamping, line endings and tab/space conversion."
  s.authors = ["John Lyon-smith"]
  s.email = "john@jamoki.com"
  s.files = [
    "lib/build_buddy.rb",
    "lib/build_server.rb",
    "lib/builder.rb",
    "lib/watcher.rb"]
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.homepage = 'http://rubygems.org/gems/build_buddy'
  s.license  = 'MIT'
  s.required_ruby_version = '~> 2.2.2'
  s.add_runtime_dependency 'celluloid', ['~> 1.2']
  s.add_runtime_dependency 'ruby-slack-client', ['~> 1.6']
  s.add_runtime_dependency 'methadone'
  s.add_runtime_dependency 'celluloid-io'
  s.add_runtime_dependency 'slack-ruby-client', ['>= 0.5.2']
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'http'
  s.add_runtime_dependency 'reel', ['>= 0.6.0.pre3']
  s.add_runtime_dependency 'configatron'
  s.add_runtime_dependency 'octokit'
end
