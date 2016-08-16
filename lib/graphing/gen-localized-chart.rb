require 'gruff'
require 'mongo'
require_relative 'constants'

# Script that generates a chart displaying localization information for past pull requests.
# Displays # strings, # descriptions, and # words.

coverage_data = []
keys = []

client = Mongo::Client.new(MONGO_URI)
db = client.database
collection = client[:builds]
collection.find().sort(:start_time => -1).limit(LIMIT).map do |document|
    pull_number = document['pull_request'].to_i
    if pull_number != 0 && !keys.include?(pull_number)
        keys.push(pull_number)
        coverage_data.insert(0, [pull_number, document['metrics']['strings'], document['metrics']['descriptions'], document['metrics']['words']])
    end
end

g = Gruff::Line.new
g.title = 'Localization'
g.labels = coverage_data.each_with_index.map {|data, i| [ i, data[0] ]}.to_h
g.dot_style = :square
g.data("# strings (#{coverage_data[coverage_data.size - 1][1]})", coverage_data.map {|data| data[1]})
g.data("# descriptions (#{coverage_data[coverage_data.size - 1][2]})", coverage_data.map {|data| data[2]})
g.data("# words (#{coverage_data[coverage_data.size - 1][3]})", coverage_data.map {|data| data[3]})
g.x_axis_label = 'Pull Request'

g.theme = {
    :colors => ['#e65954', '#0a2154', '#2a7b20'],
    :font_color => 'black',
    :background_colors => 'white'
}

g.write('output/localization_data.png')