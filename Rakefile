task :default => :test

VERSION = '1.12.0'
BUILD = '20160826.0'

task :test do
  Dir.glob('./test/test_*.rb').each { |file| require file}
end

task :vamper do
  `vamper -u`
  `git add :/`
  `git commit -m 'Update version info'`
end

task :release do
  `git tag -a 'v#{VERSION}' -m 'Release v#{VERSION}-#{BUILD}'`
  `git push --follow-tags`
  `rm *.gem`
  `gem build build-buddy.gemspec`
  `gem push build-buddy-#{VERSION}.gem`
end
