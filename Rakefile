task :default => :test

VERSION = '1.4.4'
BUILD = '20160209.0'

task :test do
  Dir.glob('./test/test_*.rb').each { |file| require file}
end

task :release do
  `vamper -u`
  `git tag -a 'v#{VERSION}' -m 'Release v#{VERSION}-#{BUILD}'`
  `git push --follow-tags`
  `rm *.gem`
  `gem build build-buddy.gemspec`
  `gem push build-buddy-#{VERSION}.gem`
end
