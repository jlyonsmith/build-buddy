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
        coverage_data.insert(0, [dateString, document['metrics']['coverage']['swift_files']['total_lines'], document['metrics']['coverage']['m_files']['total_lines']])
    end
end

g = Gruff::StackedBar.new
g.title = "Lines of Code"
g.labels = coverage_data.each_with_index.map {|data, i| [ i, data[0] ]}.to_h
g.theme = {
  :colors => ['#C17B3A', '#C1BA3A'],
  :font_color => 'black',
  :background_colors => 'white'
}
g.font = '/Library/Fonts/Verdana.ttf'
g.data("Swift (#{coverage_data[coverage_data.size - 1][1]})", coverage_data.map {|data| data[1]})
g.data("Objective-C (#{coverage_data[coverage_data.size - 1][2]})", coverage_data.map {|data| data[2]})
g.x_axis_label = 'Day'
g.y_axis_label = 'Lines of Code'
g.write "output/lines_of_code.png"
