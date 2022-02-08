# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "huginn_deposco_inventory_agent"
  spec.version       = "0.0.0"
  spec.authors       = ["Jacob Spizziri"]
  spec.email         = ["jacob.spizziri@gmail.com"]

  spec.summary       = %q{Huginn agent for sane deposco inventory data.}
  spec.description   = %q{The Huginn Deposco Inventory Agent takes in an array of SKUS, queries deposco api, and emits an event with deposco stock array merged with the event payload.}

  spec.homepage      = "https://github.com/5-Stones/huginn_deposco_inventory_agent"

  spec.license       = "MIT"


  spec.files         = Dir['LICENSE.txt', 'lib/**/*']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = Dir['spec/**/*.rb'].reject { |f| f[%r{^spec/huginn}] }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "huginn_agent"
end
