# encoding: utf-8

require 'logstash/namespace'
require 'logstash/plugin'

module LogStash
  module PluginMixins
    ##
    # This `NormalizeConfigSupport` can be included in any `LogStash::Plugin`,
    # and will provide utilities methods that can be used by the plugins to
    # extract and normalize configs.
    module NormalizeConfigSupport
      ##
      # @api internal (use: `LogStash::Plugin::include`)
      # @param base [Class]: a class that inherits `LogStash::Plugin`, typically one
      #                      descending from one of the four plugin base classes
      #                      (e.g., `LogStash::Inputs::Base`)
      # @return [void]
      def self.included(base)
        fail ArgumentError, "`#{base}` must inherit LogStash::Plugin" unless base < LogStash::Plugin
      end

      ##
      # Normalize a configuration and produces a canonical value for it.
      #
      # @yieldreturn a configurator block that can be used to configure the normalization
      # @param canonical_config the config name to produce a normalized value for
      def normalize_config(canonical_config, &configurator)
        ConfigNormalizer.new(self, canonical_config, &configurator).value
      end

      class ConfigNormalizer
        def initialize(plugin, canonical_config, &configurator)
          require_value!('canonical_config', canonical_config)
          require_value!('configurator', configurator)

          @plugin = plugin
          @canonical_config = canonical_config.to_s
          @deprecated_mappings = nil
          ensure_config_exists!(@canonical_config)

          configurator.call(self)
        end

        ##
        # Map one or more deprecated configs to the current canonical config.
        #
        # The `value_transformer` block is used when one or more deprecated configs are explicitly supplied,
        # to transform their effective values into a single suitable value for use as-if it had been
        # provided by the canonical config.
        #
        # @raise [RuntimeError] if no deprecation mappings are set for the current canonical config
        # @raise [ArgumentError] if any deprecated params provided is not marked deprecated
        # @raise [ArgumentError] if an invalid value_transformer in provided
        # @param deprecated_params [String...]: the deprecated param names
        # @return [void]
        def with_deprecated_mapping(*deprecated_params, &value_transformer)
          fail(ArgumentError, 'Deprecated mappings already configured for this config normalizer') unless @deprecated_mappings.nil?
          require_value!('deprecated_params', deprecated_params)
          ensure_deprecated!(deprecated_params)
          check_value_transformer!(deprecated_params, value_transformer)

          @deprecated_mappings = [deprecated_params.map(&:to_s), value_transformer]
        end

        ##
        # Wholly-alias a deprecated config to the current canonical config.
        # Both canonical and deprecated alias must accept the same set of values.
        #
        # @see #with_deprecated_mapping
        #
        def with_deprecated_alias(deprecated_alias)
          with_deprecated_mapping(deprecated_alias) { |v| v }
        end

        ##
        # Unambiguously extracts the effective configuration value from the canonical config and deprecated param mappings.
        # @raise `LogStash::ConfigurationError` if both canonical and deprecated params are supplied
        # @raise [RuntimeError] if no deprecation mappings are set for the current canonical config
        #
        # @return [Object]: the value of the canonical config param or an equivalent derived from provided deprecated params
        def value
          fail(ArgumentError, 'No deprecated mappings configured for this config normalizer') if @deprecated_mappings.nil?

          deprecated_params, value_transformer = @deprecated_mappings
          provided_deprecated_params = @plugin.original_params.keys.select { |k| deprecated_params.include?(k) }

          # If only the canonical config was set, return the value without apply any transformation
          return @plugin.params.fetch(@canonical_config, nil) unless provided_deprecated_params.any?

          # Both canonical and deprecated configs were set
          if @plugin.original_params.include?(@canonical_config)
            deprecated_desc = "(deprecated) `#{provided_deprecated_params.join('`,`')}`"
            raise(LogStash::ConfigurationError, "Both `#{@canonical_config}` and #{deprecated_desc} were set. Use only `#{@canonical_config}`.")
          end

          value_transformer.call(*@plugin.params.values_at(*deprecated_params))
        end

        private

        def check_value_transformer!(deprecated_params, value_transformer)
          require_value!('deprecated_params', deprecated_params)
          require_value!('value_transformer', value_transformer)
          fail ArgumentError, '`value_transformer` arity mismatch the number of deprecated params' if value_transformer.arity != deprecated_params.size
        end

        def require_value!(name, value)
          fail ArgumentError, "`#{name}` is required" if value.nil?
          fail ArgumentError, "`#{name}` cannot be empty" if value.respond_to?('empty?') && value.empty?
        end

        def ensure_deprecated!(deprecated_alias)
          deprecated_alias.each do |dp|
            ensure_config_exists!(dp)
            fail ArgumentError, "Config `#{dp}` not marked deprecated" unless @plugin.class.get_config.dig(dp.to_s, :deprecated)
          end
        end

        def ensure_config_exists!(config)
          fail ArgumentError, "Config `#{config}` does not exists" unless @plugin.class.get_config.include?(config.to_s)
        end
      end

      private_constant :ConfigNormalizer
    end
  end
end