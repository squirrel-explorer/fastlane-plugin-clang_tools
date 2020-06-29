lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/clang_tools/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-clang_tools'
  spec.version       = Fastlane::ClangTools::VERSION
  spec.author        = 'squirrel-explorer'
  spec.email         = 'xvider.zx@gmail.com'

  spec.summary       = 'A series of clang-based tools for CI/CD, including clang analyzer.'
  spec.homepage      = 'https://github.com/squirrel-explorer/fastlane-plugin-clang_tools'
  spec.license       = 'Apache 2.0'

  spec.files         = Dir['lib/**/*'] + %w[README.md LICENSE]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  # Don't add a dependency to fastlane or fastlane_re
  # since this would cause a circular dependency

  spec.add_dependency 'nokogiri'

  spec.add_development_dependency('pry')
  spec.add_development_dependency('bundler')
  spec.add_development_dependency('rake')
  spec.add_development_dependency('rspec')
  spec.add_development_dependency('rspec_junit_formatter')
  spec.add_development_dependency('rubocop')
  spec.add_development_dependency('rubocop-require_tools')
  spec.add_development_dependency('simplecov')
  spec.add_development_dependency('fastlane', '>= 2.138.0')
end
