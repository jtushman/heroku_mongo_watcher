# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "heroku_mongo_watcher/version"

Gem::Specification.new do |s|
  s.name        = "heroku_mongo_watcher"
  s.version     = HerokuMongoWatcher::VERSION
  s.authors     = ["Jonathan Tushman"]
  s.email       = ["jtushman@gmail.com"]
  s.homepage    = "https://github.com/jtushman/heroku_mongo_watcher"
  s.summary     = %q{Watches Mongostat and heroku logs to give you a pulse of your application}
  s.description = %q{Also notifies you when certain thresholds are hit.  I have found this much more accurate than New Relic}

  s.rubyforge_project = "heroku_mongo_watcher"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "term-ansicolor"
  s.add_runtime_dependency "tlsmail"
  s.add_runtime_dependency "heroku"
  s.add_runtime_dependency "trollop"
end
