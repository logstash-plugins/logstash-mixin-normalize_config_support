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
          @required_mapping = nil
          @dependent_mapping = nil
          @conflicting_mapping = nil
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
        # @raise [ArgumentError] if the deprecation mappings is already set
        # @raise [ArgumentError] if no deprecated params are provided
        # @raise [ArgumentError] if any deprecated params provided is not marked deprecated
        # @raise [ArgumentError] if any deprecated params does not exists
        # @raise [ArgumentError] if an invalid value_transformer in provided
        # @param deprecated_params [String...]: the deprecated param names
        #
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
        # Map one or more configs as required. When the canonical config is set, all required aliases
        # must have a value or default assigned.
        #
        # @raise [ArgumentError] if the required mappings is already set
        # @raise [ArgumentError] if the required aliases argument is not provided
        # @raise [ArgumentError] if any required alias does not exists
        # @param required_aliases [String...]: the required param names
        #
        # @return [void]
        #
        def with_required_aliases(*required_aliases)
          require_value!('required_aliases', required_aliases)
          fail(ArgumentError, 'Canonical config cannot be mapped as a required alias') if required_aliases.include?(@canonical_config)
          fail(ArgumentError, 'Required aliases mappings already configured for this config normalizer') unless @required_mapping.nil?
          ensure_configs_exists!(required_aliases)

          @required_mapping = required_aliases.map(&:to_s)
        end

        ##
        # Map one or more configs as dependent of the current canonical config.
        # If any dependent aliases are provided, the canonical config must also have a value defined.
        # @raise [ArgumentError] if the dependent_aliases includes the canonical config
        # @raise [ArgumentError] if the dependent mappings is already set
        # @raise [ArgumentError] if the dependent aliases argument is not provided
        # @raise [ArgumentError] if any dependent alias does not exists
        # @param dependent_aliases [String...]: the param names that depends on the current canonical config
        #
        # @return [void]
        #
        def with_dependent_aliases(*dependent_aliases)
          require_value!('dependent_aliases', dependent_aliases)
          fail(ArgumentError, 'Canonical config cannot be mapped as a dependent alias') if dependent_aliases.include?(@canonical_config)
          fail(ArgumentError, 'Dependent aliases mappings already configured for this config normalizer') unless @dependent_mapping.nil?
          ensure_configs_exists!(dependent_aliases)

          @dependent_mapping = dependent_aliases.map(&:to_s)
        end

        ##
        # Map one or more configs that conflicts with the current canonical config.
        # If the canonical config value is provided, all conflicting aliases must not be set.
        # @raise [ArgumentError] if the dependent_aliases includes the canonical config
        # @raise [ArgumentError] if the conflicting mappings is already set
        # @raise [ArgumentError] if the conflicting aliases argument is not provided
        # @raise [ArgumentError] if any conflicting alias does not exists
        # @param conflicting_aliases [String...]: the param names that conflicts with the current canonical config
        #
        # @return [void]
        #
        def with_conflicting_aliases(*conflicting_aliases)
          require_value!('conflicting_aliases', conflicting_aliases)
          fail(ArgumentError, 'Canonical config cannot be mapped as a conflicting alias') if conflicting_aliases.include?(@canonical_config)
          fail(ArgumentError, 'Conflicting aliases mappings already configured for this config normalizer') unless @conflicting_mapping.nil?
          ensure_configs_exists!(conflicting_aliases)

          @conflicting_mapping = conflicting_aliases.map(&:to_s)
        end


        ##
        # Unambiguously extracts the effective configuration value from the canonical config and deprecated param mappings.
        # @raise [LogStash::ConfigurationError] if both canonical and deprecated params are supplied
        # @raise [LogStash::ConfigurationError] if any required alias is not supplied
        # @raise [LogStash::ConfigurationError] if any dependent alias is set and effective value is nil
        #
        # @return [Object]: the value of the canonical config param or an equivalent derived from provided deprecated params
        def value
          validate_required_aliases!
          validate_dependent_aliases!
          validate_conflicting_aliases!

          extract_effective_value
        end

        private

        def extract_effective_value
          if deprecated_mappings?
            return deprecated_canonical_value!
          end

          @plugin.params.fetch(@canonical_config, nil)
        end

        def deprecated_mappings?
          @deprecated_mappings&.any?
        end

        def deprecated_canonical_value!
          deprecated_params, value_transformer = @deprecated_mappings
          provided_deprecated_params = @plugin.original_params.keys.select { |k| deprecated_params.include?(k) }

          # If only the canonical config was set, return the value without apply any transformation
          if provided_deprecated_params.empty?
            @plugin.params.fetch(@canonical_config, nil)
          else
            # Both canonical and deprecated configs were set
            if @plugin.original_params.include?(@canonical_config)
              deprecated_desc = "(deprecated) `#{provided_deprecated_params.join('`,`')}`"
              raise(LogStash::ConfigurationError, "Both `#{@canonical_config}` and #{deprecated_desc} were set. Use only `#{@canonical_config}`.")
            end

            value_transformer.call(*@plugin.params.values_at(*deprecated_params))
          end
        end

        def validate_required_aliases!
          canonical_config_value = @plugin.params.fetch(@canonical_config, nil)

          if @required_mapping&.any? && !canonical_config_value.nil?
            required_param_values = @plugin.params.values_at(*@required_mapping)
            nil_values_index = required_param_values.each_index.select { |i| required_param_values[i] == nil }

            unless nil_values_index.empty?
              nil_param_names = @required_mapping.values_at(*nil_values_index).map { |v| "`#{v}`" }.join(", ")
              raise(LogStash::ConfigurationError, "Config `#{@canonical_config}` requires #{nil_param_names} to be set")
            end
          end
        end

        def validate_dependent_aliases!
          if @dependent_mapping&.any? && @plugin.params.fetch(@canonical_config, nil).nil?
            dependent_param_values = @plugin.original_params.values_at(*@dependent_mapping)
            set_config_index = dependent_param_values.each_index.select { |i| dependent_param_values[i] != nil }

            unless set_config_index.empty?
              set_param_names = @dependent_mapping.values_at(*set_config_index).map { |v| "`#{v}`" }.join(", ")
              raise(LogStash::ConfigurationError, "Configs #{set_param_names} requires `#{@canonical_config}` to be set")
            end
          end
        end

        def validate_conflicting_aliases!
          if @conflicting_mapping&.any? && @plugin.original_params.key?(@canonical_config)
            conflicting_param_values = @plugin.original_params.values_at(*@conflicting_mapping)
            conflicting_values_index = conflicting_param_values.each_index.select { |i| conflicting_param_values[i] != nil }

            unless conflicting_values_index.empty?
              conflicting_param_names = @conflicting_mapping.values_at(*conflicting_values_index).map { |v| "`#{v}`" }.join(", ")
              raise(LogStash::ConfigurationError, "Use either `#{@canonical_config}` or #{conflicting_param_names}")
            end
          end
        end

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

        def ensure_configs_exists!(configs)
          configs.each do |cfg|
            ensure_config_exists!(cfg)
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