Gem::Specification.new do |spec|
  spec.name          = "microbuild"
  spec.version       = "0.1.0"
  spec.authors       = ["microbuild"]
  spec.summary       = "A small Ruby scripting system for building C and C++ applications"
  spec.description   = "Provides a Builder class that detects C/C++ compilers and wraps compile and link operations"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7"

  spec.add_development_dependency "rspec", "~> 3.0"
end
