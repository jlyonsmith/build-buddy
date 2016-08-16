require 'gruff'
require 'mongo'
require_relative 'constants'

# Script that generates a chart displaying build time information for past pull requests.

coverage_data = []
keys = []

client = Mongo::Client.new(MONGO_URI)
db = client.database
collection = client[:builds]
collection.find().sort(:start_time => -1).limit(LIMIT).map do |document|
    pull_number = document['pull_request'].to_i
    if pull_number != 0 && !keys.include?(pull_number) && document['metrics']['test_build_end'] != nil && document['metrics']['test_build_start'] != nil
        endTimeComponents = document['metrics']['test_build_end'].to_s.split(' ')[1].split(':')
        endDateComponents = document['metrics']['test_build_end'].to_s.split(' ')[0].split('-')
        endTime = Time.new(endDateComponents[0], endDateComponents[1], endDateComponents[2], endTimeComponents[0], endTimeComponents[1], endTimeComponents[2])

    startTimeComponents = document['metrics']['test_build_start'].to_s.split(' ')[1].split(':')
    startDateComponents = document['metrics']['test_build_start'].to_s.split(' ')[0].split('-')
    startTime = Time.new(startDateComponents[0], startDateComponents[1], startDateComponents[2], startTimeComponents[0], startTimeComponents[1], startTimeComponents[2])
    
    buildTimeMins = ((endTime - startTime) / 60).to_f.round(2)

        keys.push(pull_number)
        coverage_data.insert(0, [pull_number, buildTimeMins])
    end
end

g = Gruff::Line.new
g.minimum_value = 0
g.maximum_value = 10
g.title = 'Build Times'
g.labels = coverage_data.each_with_index.map {|data, i| [ i, data[0] ]}.to_h
g.dot_style = :square
g.data("minutes (#{coverage_data[coverage_data.size - 1][1]})", coverage_data.map {|data| data[1]})
g.x_axis_label = 'Pull Request'
g.y_axis_label = 'Time (mins)'

g.theme = {
    :colors => ['#38c0df'],
    :font_color => 'black',
    :background_colors => 'white'
}

g.write('output/build_times.png')