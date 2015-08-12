#!/usr/bin/env ruby
$:.unshift File.expand_path File.join File.dirname(__FILE__), '../lib'
require 'rubygems'
require 'bundler/setup'
require 'cryptcheck'

name = ARGV[0] || 'index'
file = ::File.join 'output', "#{name}.yml"

if ::File.exist? file
	::CryptCheck::Logger.level = :none
	::CryptCheck::Tls::Https.analyze_from_file "output/#{name}.yml", "output/#{name}.html"
else
	::CryptCheck::Logger.level = :info
	server = ::CryptCheck::Tls::Https::Server.new(ARGV[0], ARGV[1] || 443)
	grade = ::CryptCheck::Tls::Https::Grade.new server
	::CryptCheck::Logger.info { '' }
	grade.display
end
