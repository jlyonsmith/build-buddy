#!/usr/bin/env ruby

# Runs all chart generators.

require_relative 'gen-cov-chart'
require_relative 'gen-warn-chart'
require_relative 'gen-times-chart'
require_relative 'gen-localized-chart'
require_relative 'gen-builds-chart'
require_relative 'gen-lines-chart'