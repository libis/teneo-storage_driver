require "date"

require_relative "lib/teneo/storage_driver/version"

Gem::Specification.new do |spec|
  spec.name = "teneo-storage_driver"
  spec.version = Teneo::StorageDriver::VERSION
  spec.authors = ["Kris Dekeyser"]
  spec.email = ["kris.dekeyser@kuleuven.be"]

  spec.summary = %q{StorageDriver library for Teneo.}
  spec.description = %q{This gem contains the supported storage drivers for Teneo.}
  spec.homepage = "https://github.com/Libis/teneo-storage_driver"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/libis"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage + "/CHANGELOG.md"

  spec.platform = Gem::Platform::JAVA if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
