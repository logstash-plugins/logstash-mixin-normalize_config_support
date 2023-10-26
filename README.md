# Normalize Config Support Mixin

[![Build Status](https://travis-ci.com/logstash-plugins/logstash-mixin-normalize_config_support.svg?branch=main)](https://travis-ci.com/logstash-plugins/logstash-mixin-normalize_config_support)

This gem can be included in any `LogStash::Plugin`, and will provide utilities methods
that can be used by the plugins to
extract and normalize configs.

## Usage

1. Add version `~>1.1` of this gem as a runtime dependency of your Logstash
   plugin's `gemspec`:

    ~~~ ruby
    Gem::Specification.new do |s|
      # ...

      s.add_runtime_dependency 'logstash-mixin-normalize_config_support', '~>1.0'
    end
    ~~~

2. In your plugin code, require this library and include it into your plugin class
   that already inherits `LogStash::Plugin`:

    ~~~ ruby
    require 'logstash/plugin_mixins/normalize_config_support'

    class LogStash::Inputs::Foo < Logstash::Inputs::Base
      include LogStash::PluginMixins::NormalizeConfigSupport

      # ...
    end
    ~~~

3. Use the provided `normalize_config` method to normalize a configuration and to
   produce a canonical value for it.
   It currently supports the following normalizers:
    - `with_deprecated_mapping`: Map one or more deprecated configs to the canonical
      config
    - `with_deprecated_alias`: Wholly-alias a deprecated config to the canonical
      config
    - `with_required_aliases`: Map one or more configs as required. When the canonical 
      config is set, all required aliases must have a value or default.
    - `with_dependent_aliases`: Map one or more configs as dependent of the current canonical config.
      If any dependent aliases are provided, the canonical config must also be provided.
    - `with_conflicting_aliases`: Map one or more configs that conflicts with the current canonical config.
      If the canonical config value is provided, all conflicting aliases must not be set.


   ~~~ ruby
   def register
     # ...
     @ssl_verification_mode = normalize_config(:ssl_verification_mode) do |normalize|
        normalize.with_deprecated_mapping(:ssl_verify_mode) do |ssl_verify_mode|
           case ssl_verify_mode
           when "none"       then "none"
           when "peer"       then "certificate"
           when "force_peer" then "full"
           else fail(LogStash::ConfigurationError, "Unsupported value #{ssl_verify_mode} for deprecated option `ssl_verify_mode`")
        end
     end

     @ssl_cipher_suites = normalize_config(:ssl_cipher_suites) do |normalize|
        normalize.with_deprecated_alias(:cipher_suites)
     end

     @ssl_supported_protocols = normalize_config(:ssl_supported_protocols) do |normalize|
        normalize.with_deprecated_mapping(:tls_min_version, :tls_max_version) do |tls_min, tls_max|
           TLS.get_supported(tls_min..tls_max).map(&:name)
        end
     end
   
     @ssl_truststore_path = normalize_config(:ssl_truststore_path) do |normalize|
        normalize.with_deprecated_alias(:truststore)
        normalize.with_dependent_aliases(:ssl_truststore_password, :ssl_truststore_type)
     end
   
     normalize_config(:ssl_certificate) do |normalize|
        normalize.with_deprecated_alias(:client_cert) 
        normalize.with_required_aliases(:ssl_key)
        normalize.with_conflicting_aliases(:ssl_keystore_path, :ssl_keystore_password, :ssl_keystore_type)
     end
   end
   ~~~

## Development

This gem:

- *MUST NOT* introduce additional runtime dependencies
