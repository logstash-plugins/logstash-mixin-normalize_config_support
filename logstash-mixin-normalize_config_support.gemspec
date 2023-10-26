Gem::Specification.new do |s|
  s.name          = 'logstash-mixin-normalize_config_support'
  s.version       = "1.1.0"
  s.licenses      = %w(Apache-2.0)
  s.summary       = "Support for Logstash plugins wishing to deprecate config options"
  s.description   = "This gem is meant to be a dependency of any Logstash plugin that needs to normalize config options, supporting canonical options along-side deprecated options"
  s.authors       = %w(Elastic)
  s.email         = 'info@elastic.co'
  s.homepage      = 'https://github.com/logstash-plugins/logstash-mixin-normalize_config_support'
  s.require_paths = %w(lib)

  s.files = %w(ext lib spec vendor).flat_map{|dir| Dir.glob("#{dir}/**/*")}+Dir.glob(["*.md","LICENSE"])

  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  s.platform = RUBY_PLATFORM

  s.add_runtime_dependency 'logstash-core', '>= 6.8.0'
  s.add_development_dependency 'logstash-devutils'
  s.add_development_dependency 'rspec', '~> 3.9'
  s.add_development_dependency 'rspec-its', '~>1.3'
  s.add_development_dependency 'logstash-codec-plain', '>= 3.1.0'
end
