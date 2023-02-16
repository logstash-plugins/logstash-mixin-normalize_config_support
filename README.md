# Config Deprecation Support Mixin

[![Build Status](https://travis-ci.com/logstash-plugins/logstash-mixin-config_deprecation_support.svg?branch=main)](https://travis-ci.com/logstash-plugins/logstash-mixin-config_deprecation_support)

This gem can be included in any `LogStash::Plugin`, and will provide utilities methods that can be used by the plugins to
extract and deprecate config values.

## Usage

1. Add version `~>1.0` of this gem as a runtime dependency of your Logstash plugin's `gemspec`:

    ~~~ ruby
    Gem::Specification.new do |s|
      # ...

      s.add_runtime_dependency 'logstash-mixin-plugin_factory_support', '~>1.0'
    end
    ~~~

2. In your plugin code, require this library and include it into your plugin class
   that already inherits `LogStash::Plugin`:

    ~~~ ruby
    require 'logstash/plugin_mixins/config_deprecation_support'

    class LogStash::Inputs::Foo < Logstash::Inputs::Base
      include LogStash::PluginMixins::ConfigDeprecationSupport

      # ...
    end
    ~~~

3. Use the provided `config_with_deprecated_target!` method to unambiguously extracts the
   value of a param that may be provided with one or more deprecated params:

    ~~~ ruby
    def register
      # ...
      @ssl_enabled_final = config_with_deprecated_target!('ssl_enabled', 'ssl')
    end
    ~~~

    ~~~ ruby
    def register
      # ...
      @ssl_protocols_final = config_with_deprecated_target!('ssl_supported_protocols', 'tls_min_version', 'tls_max_version') do |tls_min, tls_max|
        TLS.supported_protocols(tls_min..tls_max)
      end
    end
    ~~~
   
4. Use the provided `config_with_deprecated_value!` method to extract the value of a param 
   that may be provided with one or more deprecated values. This method also emits deprecation 
   logs if any value is transformed by the provided block:

    ~~~ ruby
    def register
      # ...
      @ssl_verify_mode_final = config_with_deprecated_value!('ssl_verify_mode') do |value|
        case value
          when "peer"
            "certificate"
          when "force_peer"
            "full"
          else
            value
        end
      end
    end
    ~~~

   A custom equality comparator method can be provided to compare complex config types:
   ~~~ ruby
    def register
      # ...
       @ssl_protocols_final = config_with_deprecated_value!('ssl_supported_protocols', -> value, transformed_value {
          value.sort == transformed_value.sort 
        }) do |supported_protocols|
            %w[TLSv1.2, TLSv1.1, TLSv1.3]
        end
    end
   ~~~  



   
## Development

This gem:
- *MUST NOT* introduce additional runtime dependencies
