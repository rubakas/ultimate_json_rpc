# frozen_string_literal: true

require_relative "lib/ultimate_json_rpc/version"

Gem::Specification.new do |spec|
  spec.name = "ultimate_json_rpc"
  spec.version = UltimateJsonRpc::VERSION
  spec.authors = ["Andriy Tyurnikov"]
  spec.email = ["Andriy.Tyurnikov@gmail.com"]

  spec.summary = "Expose Ruby objects through JSON-RPC"
  spec.description = "Network-agnostic JSON-RPC server that exposes Ruby modules, classes, " \
                     "instances, and namespaces as callable RPC endpoints."
  spec.homepage = "https://github.com/rubakas/ultimate_json_rpc"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rubakas/ultimate_json_rpc"
  spec.metadata["changelog_uri"] = "https://github.com/rubakas/ultimate_json_rpc/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml .claude/]) ||
        f.end_with?("PRD.md", "CLAUDE.md")
    end
  end
  spec.require_paths = ["lib"]
end
