# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "microbuild"
  spec.version       = "0.1.0"
  spec.authors       = ["microbuild"]
  spec.email         = "psadda@gmail.com"
  spec.summary       = "A small Ruby scripting system for building C and C++ applications"
  spec.description   = <<~DESC
    microbuild provides a small set of classes for invoking C/C++ build tools, abstracting
    away differences between compilers.
  DESC
  spec.license       = "BSD-3-Clause"

  spec.files         = Dir["lib/**/*.rb"] + Dir["bin/*"]
  spec.executables   = ["microbuild"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["rubygems_mfa_required"] = "true"
end
