# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "paper_trail/compatibility"
require "paper_trail/version_number"

Gem::Specification.new do |s|
  s.name = "paper_trail"
  s.version = PaperTrail::VERSION::STRING
  s.platform = Gem::Platform::RUBY
  s.summary = "PaperTrail DropIn replacement to store version in MongoDB"
  s.description = <<-EOS
PaperTrail DropIn replacement to store version in MongoDB
  EOS
  s.homepage = "https://github.com/noma4i/mongo-trail"
  s.authors = ["Alex Tsirel","Ivan Romanyuk"]
  s.email = "noma4i@gmail.com"
  s.license = "MIT"

  s.files = `git ls-files -z`.split("\x0").select { |f|
    f.match(%r{^(Gemfile|LICENSE|lib|paper_trail.gemspec)/})
  }
  s.executables = []
  s.require_paths = ["lib"]

  s.add_dependency "activerecord", ::PaperTrail::Compatibility::ACTIVERECORD_GTE
  s.add_dependency "request_store", "~> 1.1"
  s.add_dependency "mongoid", "~> 6.0"
  s.add_dependency "mongoid-autoinc", "< 7"
end
