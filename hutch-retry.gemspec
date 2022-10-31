# frozen_string_literal: true

require File.expand_path('../lib/hutch/retry/version', __FILE__)

Gem::Specification.new do |spec|
  spec.name = "hutch-retry"
  spec.version = Hutch::Retry::VERSION
  spec.authors = ["Michał Marcinkowski"]
  spec.email = ["michal@marcinkowski.io"]

  spec.summary = "TBD"
  spec.description = "TBD"
  spec.homepage = "https://www.github.com/Motimate/hutch-retry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "hutch", "1.1.1"
end
