# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dockistrano/version'

Gem::Specification.new do |spec|
  spec.name          = "dockistrano"
  spec.version       = Dockistrano::VERSION
  spec.authors       = ["Edwin Vlieg"]
  spec.email         = ["edwin@moneybird.com"]
  spec.summary       = %q{Manage Docker containers for a development workflow}
  spec.homepage      = "http://github.com/moneybird/dockistrano"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_dependency "cocaine"
  spec.add_dependency "multi_json"
  spec.add_dependency "redis"
  spec.add_dependency "dotenv"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-rspec"
  spec.add_development_dependency "guard-shell"
  spec.add_development_dependency "ruby_gntp"
  spec.add_development_dependency "terminal-notifier-guard"
  spec.add_development_dependency "webmock"
end
