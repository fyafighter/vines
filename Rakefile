require 'rake'
require 'rake/gempackagetask'

GEM_VERSION = "0.1.0"

spec = Gem::Specification.new do |s| 
  s.name = "vines-xmpp"
  s.version = GEM_VERSION
  s.summary = "Vines is an XMPP server capable of chatting with large clusters of servers."
  s.description = "Vines is a sophisticated XMPP server capable of chatting with large groups
of servers (and humans!). Servers can be grouped together using a simple query syntax. Commands
can be run on a group, effectively controling many servers at the same time,
using any standard XMPP client (iChat, Pidgin, Adium, etc.)"
  s.files = FileList["{bin,lib}/**/*"].to_a
  s.require_path = "lib"
  s.test_files = FileList["{test}/**/*test.rb"].to_a
  s.has_rdoc = true
  s.required_ruby_version = '>= 1.8.6'
  s.add_dependency("eventmachine", ">= 0.12.11")
  s.add_dependency("session", ">= 2.4.0")
  s.add_dependency("xmpp4r", ">= 0.5.0")
  s.add_dependency("couchrest", ">= 0.35.0")
  s.add_dependency("ruby-net-ldap", ">= 0.0.4")
  s.add_dependency("activerecord", ">= 2.3.5")
  s.add_dependency("sqlite3-ruby", ">= 1.2.5")
  s.add_dependency("thin", ">= 1.2.7")
  s.add_dependency("nokogiri", ">= 1.4.1")
end
 
Rake::GemPackageTask.new(spec) do |pkg| 
  pkg.need_tar = true 
end 

task :default => :gem
