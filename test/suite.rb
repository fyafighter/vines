# Run this file with 'ruby suite.rb' to run the full test suite.

require 'test/unit'
require 'rubygems'

dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift(File.join(dir, '../lib'))

require 'vines'
require 'storage/storage_tests'
Dir.glob("#{dir}/**/*test.rb").each {|f| puts f;require f }
