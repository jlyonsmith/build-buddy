require 'gruff'
require 'mongo'
require_relative 'constants'

# Script that generates a chart displaying number of lines of code by Swift/Objective-C.

coverage_data = []
keys = []

client = Mongo::Client.new(MONGO_URI)
db = client.database
collection = client[:builds]
collection.find().sort(:start_time => -1).limit(LIMIT).map do |document|
    startDateComponents = document['start_time'].to_s.split(' ')[0].split('-')
    
    dateString = startDateComponents[1] + "/" + startDateComponents[2]

    pull_number = document['pull_request'].to_i
    if pull_number == 0 && document['metrics']['coverage'] != nil && !keys.include?(dateString)
        keys.push(dateString)
        
        missedLines = document['metrics']['coverage']['swift_files']['missed_lines'] + document['metrics']['coverage']['m_files']['missed_lines']
        totalLines = document['metrics']['coverage']['swift_files']['total_lines'] + document['metrics']['coverage']['m_files']['total_lines']
        covPercent = ((1.0 * (totalLines - missedLines) / totalLines) * 100).to_i
        coverage_data.insert(0, [dateString, covPercent])
    end
end

g = Gruff::Bar.new
g.minimum_value = 0
g.maximum_value = 100
g.title = "Coverage"
g.labels = coverage_data.each_with_index.map {|data, i| [ i, data[0] ]}.to_h
g.theme = {
    :colors => ['#822F92'],
    :font_color => 'black',
    :background_colors => 'white'
}
g.font = '/Library/Fonts/Verdana.ttf'
g.data("covered % (#{coverage_data[coverage_data.size - 1][1]})", coverage_data.map {|data| data[1]})
g.x_axis_label = 'Date'
g.y_axis_label = 'Coverage %'
g.write "output/code_coverage.png"