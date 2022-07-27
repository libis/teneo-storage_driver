require 'date'

require_relative "lib/teneo/storage_driver/version"

Gem::Specification.new do |spec|
  spec.name          = 'teneo-storage_driver'
  spec.version       = Teneo::StorageDriver::VERSION
  spec.date          = Date.today.to_s

  spec.summary       = %q{StorageDriver library for Teneo.}
  spec.description   = %q{This gem contains the supported storage drivers for Teneo.}

  spec.authors       = ['Kris Dekeyser']
  spec.email         = ['kris.dekeyser@libis.be']
  spec.homepage      = 'https://github.com/Libis/teneo-storage_driver'
  spec.license       = 'MIT'

  spec.platform     = Gem::Platform::JAVA if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'

  spec.files         = `git ls-files -z`.split("\x0").delete_if {|name| name =~ /^(spec\/|\.travis|\.git)/ }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.require_paths = ['lib']
  spec.required_ruby_version = ">= 3.0.0"

end
