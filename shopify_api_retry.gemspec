Gem::Specification.new do |spec|
  spec.name          = "shopify_api_retry"
  spec.version       = "0.2.0"
  spec.authors       = ["Skye Shaw"]
  spec.email         = ["skye.shaw@gmail.com"]

  spec.summary       = %q{Retry a ShopifyAPI request if if rate-limited or other errors occur. Works with the REST and GraphQL APIs.}
  spec.homepage      = "https://github.com/ScreenStaring/shopify_api_retry"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.3"
  spec.add_dependency "shopify_api", ">= 4.0"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 12.0"
end
