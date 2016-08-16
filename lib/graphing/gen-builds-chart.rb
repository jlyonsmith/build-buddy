require 'gruff'
require 'mongo'
require_relative 'constants'

# Script that generates a chart displaying number of builds per day by branch/PR.

coverage_data = []
keys = []

client = Mongo::Client.new(MONGO_URI)
db = client.database
collection = client[:builds]
collection.find().sort(:start_time => -1).limit(LIMIT).map do |document|
    
    startDateComponents = document['start_time'].to_s.split(' ')[0].split('-')
        
    dateString = startDateComponents[1] + "/" + startDateComponents[2]
    
    if keys.include?(dateString)
        coverage_data.each { |arr|
            if arr[0] == dateString
                if document['pull_request'] != nil
                    arr[1] = arr[1] + 1
                else
                    arr[2] = arr[2] + 1
                end
            end
        }
    else
        keys.push(dateString)
        if document['pull_request'] != nil
            coverage_data.insert(0, [dateString, 1, 0])
        else
            coverage_data.insert(0, [dateString, 0, 1])
        end
    end
end

g = Gruff::StackedBar.new
g.title = "Builds per Day"
g.labels = coverage_data.each_with_index.map {|data, i| [ i, data[0] ]}.to_h
g.theme = {
  :colors => ['#12a702', '#aedaa9'],
  :font_color => 'black',
  :background_colors => 'white'
}
g.font = '/Library/Fonts/Verdana.ttf'
g.data("Pull Request (#{coverage_data[coverage_data.size - 1][1]})", coverage_data.map {|data| data[1]})
g.data("Other (#{coverage_data[coverage_data.size - 1][2]})", coverage_data.map {|data| data[2]})
g.x_axis_label = 'Date'
g.y_axis_label = 'Number of Builds'
g.y_axis_increment = 2
g.write "output/daily-builds.png"
