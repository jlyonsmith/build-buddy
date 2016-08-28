require 'rubygems'
require 'bundler'
require 'celluloid'
require 'mongo'
require 'gruff'
require_relative './config.rb'

module BuildBuddy
  class Recorder
    include Celluloid
    include Celluloid::Internals::Logger

    LIMIT = 50

    def initialize()
      Mongo::Logger.logger.level = ::Logger::FATAL
      mongo_uri = BuildBuddy::Config.mongo_uri
      @mongo ||= Mongo::Client.new(mongo_uri)
      info "Connected to MongoDB at '#{mongo_uri}'"
      @mongo[:builds].indexes.create_one({:start_time => -1}, :name => "reverse_build_order")
    end

    def record_build_data(build_data)
      builds = @mongo[:builds]
      result = builds.insert_one(build_data.to_h)
      if build_data._id.nil?
        build_data._id = result.inserted_id
      end
    end

    def update_build_data(build_data)
      if build_data._id.nil?
        return
      end

      builds = @mongo[:builds]
      builds.replace_one({ :_id => build_data._id }, build_data.to_h)

      gen_charts
    end

    def get_build_data(id)
      doc = @mongo[:builds].find({ :_id => BSON::ObjectId.from_string(id) }, { :limit => 1 }).first
      if doc.nil?
        return nil
      end
      BuildData.new(doc)
    end

    def get_build_data_history(limit)
      @mongo[:builds].find().sort(:start_time => -1).limit(limit).map do |doc|
        BuildData.new(doc)
      end
    end
    
    def gen_charts
      gen_daily_builds_chart
      gen_coverage_chart
      gen_lines_chart
      gen_localized_chart
      gen_times_chart
      gen_warnings_chart
    end
    
    def gen_daily_builds_chart
      # Generates a chart showing builds per day
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).each do |doc|
        next if doc['start_time'].nil?
        start_data_components = doc['start_time'].to_s.split(' ')[0].split('-')
        date_string = start_data_components[1] + "/" + start_data_components[2]
    
        if keys.include?(date_string)
          data.each { |arr|
            if arr[0] == date_string
              if doc['pull_request'] != nil
                arr[1] = arr[1] + 1
              else
                arr[2] = arr[2] + 1
              end
            end
          }
        else
          keys.push(date_string)
          if doc['pull_request'] != nil
            data.insert(0, [date_string, 1, 0])
          else
            data.insert(0, [date_string, 0, 1])
          end
        end
        end
  
      g = Gruff::StackedBar.new
      g.title = "Builds per Day"
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.theme = {
          :colors => ['#12a702', '#aedaa9'],
          :font_color => 'black',
          :background_colors => 'white'
      }
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("Pull Request (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.data("Other (#{data.size > 0 ? data[data.size - 1][2] : 0})", data.map {|d| d[2]})
      g.x_axis_label = 'Date'
      g.y_axis_label = 'Number of Builds'
      g.y_axis_increment = 2
      g.write File.join(Config.hud_image_dir, "daily_builds.png")
    end

    def gen_coverage_chart
      # Generate code coverage numbers
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).map do |doc|
        next if doc['start_time'].nil?
        start_date_components = doc['start_time'].to_s.split(' ')[0].split('-')
        date_string = start_date_components[1] + "/" + start_date_components[2]
        pull_number = doc['pull_request'].to_i
        if pull_number == 0 && doc['metrics']['coverage'] != nil && !keys.include?(date_string)
          keys.push(date_string)

          missed_lines = doc['metrics']['coverage']['swift_files']['missed_lines'] + doc['metrics']['coverage']['m_files']['missed_lines']
          total_lines = doc['metrics']['coverage']['swift_files']['total_lines'] + doc['metrics']['coverage']['m_files']['total_lines']
          coverage_percent = ((1.0 * (total_lines - missed_lines) / total_lines) * 100).to_i
          data.insert(0, [date_string, coverage_percent])
        end
      end

      g = Gruff::Bar.new
      g.minimum_value = 0
      g.maximum_value = 100
      g.title = "Coverage"
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.theme = {
          :colors => ['#822F92'],
          :font_color => 'black',
          :background_colors => 'white'
      }
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("covered % (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.x_axis_label = 'Date'
      g.y_axis_label = 'Coverage %'
      g.write File.join(Config.hud_image_dir, "code_coverage.png")    
    end

    def gen_lines_chart
      # Generates a chart displaying number of lines of code by Swift/Objective-C.
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).map do |doc|
        next if doc['start_time'].nil?
        start_date_components = doc['start_time'].to_s.split(' ')[0].split('-')
        date_string = start_date_components[1] + "/" + start_date_components[2]
        pull_number = doc['pull_request'].to_i
        if pull_number == 0 && doc['metrics']['coverage'] != nil && !keys.include?(date_string)
          keys.push(date_string)
          data.insert(0, [date_string, doc['metrics']['coverage']['swift_files']['total_lines'], doc['metrics']['coverage']['m_files']['total_lines']])
        end
      end

      g = Gruff::StackedBar.new
      g.title = "Lines of Code"
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.theme = {
          :colors => ['#C17B3A', '#C1BA3A'],
          :font_color => 'black',
          :background_colors => 'white'
      }
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("Swift (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.data("Objective-C (#{data.size > 0 ? data[data.size - 1][2] : 0})", data.map {|d| d[2]})
      g.x_axis_label = 'Day'
      g.y_axis_label = 'Lines of Code'
      g.write File.join(Config.hud_image_dir, "lines_of_code.png")
    end

    def gen_localized_chart
      # Generates a chart displaying localization information for past pull requests.
      # Displays # strings, # descriptions, and # words.
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).map do |doc|
        pull_number = doc['pull_request'].to_i
        if pull_number != 0 && !keys.include?(pull_number)
          keys.push(pull_number)
          data.insert(0, [pull_number, doc['metrics']['strings'], doc['metrics']['descriptions'], doc['metrics']['words']])
        end
      end

      g = Gruff::Line.new
      g.title = 'Localization'
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.dot_style = :square
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("# strings (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.data("# descriptions (#{data.size > 0 ? data[data.size - 1][2] : 0})", data.map {|d| d[2]})
      g.data("# words (#{data.size > 0 ? data[data.size - 1][3] : 0})", data.map {|d| d[3]})
      g.x_axis_label = 'Pull Request'

      g.theme = {
          :colors => ['#e65954', '#0a2154', '#2a7b20'],
          :font_color => 'black',
          :background_colors => 'white'
      }

      g.write(File.join(Config.hud_image_dir, 'localization_data.png'))
    end

    def gen_times_chart
      # Generates a chart displaying build time information for past pull requests.
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).map do |doc|
        next if doc['metrics'].nil?
        pull_number = doc['pull_request'].to_i
        if pull_number != 0 && !keys.include?(pull_number) && doc['metrics']['test_build_end'] != nil && doc['metrics']['test_build_start'] != nil
          end_time_components = doc['metrics']['test_build_end'].to_s.split(' ')[1].split(':')
          end_date_components = doc['metrics']['test_build_end'].to_s.split(' ')[0].split('-')
          end_time = Time.new(end_date_components[0], end_date_components[1], end_date_components[2], end_time_components[0], end_time_components[1], end_time_components[2])

          start_time_components = doc['metrics']['test_build_start'].to_s.split(' ')[1].split(':')
          start_date_components = doc['metrics']['test_build_start'].to_s.split(' ')[0].split('-')
          start_time = Time.new(start_date_components[0], start_date_components[1], start_date_components[2], start_time_components[0], start_time_components[1], start_time_components[2])

          build_time_mins = ((end_time - start_time) / 60).to_f.round(2)

          keys.push(pull_number)
          data.insert(0, [pull_number, build_time_mins])
        end
      end

      g = Gruff::Line.new
      g.minimum_value = 0
      g.maximum_value = 10
      g.title = 'Build Times'
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.dot_style = :square
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("minutes (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.x_axis_label = 'Pull Request'
      g.y_axis_label = 'Time (mins)'
      g.theme = {
          :colors => ['#38c0df'],
          :font_color => 'black',
          :background_colors => 'white'
      }

      g.write(File.join(Config.hud_image_dir, 'build_times.png'))
    end

    def gen_warnings_chart
      # Script that generates a chart displaying warning count information for past pull requests.
      data = []
      keys = []
      @mongo[:builds].find().sort(:start_time => -1).limit(LIMIT).map do |doc|
        next if doc['start_time'].nil?
        start_date_components = doc['start_time'].to_s.split(' ')[0].split('-')
        date_string = start_date_components[1] + "/" + start_date_components[2]
        pull_number = doc['pull_request'].to_i
        if pull_number == 0 && doc['metrics']['test_build_start'] != nil && !keys.include?(date_string)
          keys.push(date_string)
          data.insert(0, [date_string, doc['metrics']['warning_count']])
        end
      end

      g = Gruff::Line.new
      g.title = 'Warnings'
      g.labels = data.each_with_index.map {|d, i| [ i, d[0] ]}.to_h
      g.dot_style = :square
      g.font = '/Library/Fonts/Verdana.ttf'
      g.data("# warnings (#{data.size > 0 ? data[data.size - 1][1] : 0})", data.map {|d| d[1]})
      g.x_axis_label = 'Date'
      g.y_axis_label = 'Number of Warnings'
      g.theme = {
          :colors => ['#c3a00b'],
          :font_color => 'black',
          :background_colors => 'white'
      }
      g.write(File.join(Config.hud_image_dir, 'warning_count.png'))
    end
  end
end