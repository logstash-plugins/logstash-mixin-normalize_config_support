# encoding: utf-8

require 'logstash/namespace'
require 'logstash/plugin'

module LogStash
  module PluginMixins
    ##
    # This `ConfigDeprecationSupport` can be included in any `LogStash::Plugin`,
    # and will provide utilities methods that can be used by the plugins to
    # extract and deprecate configs.
    module ConfigDeprecationSupport
      ##
      # @api internal (use: `LogStash::Plugin::include`)
      # @param base [Class]: a class that inherits `LogStash::Plugin`, typically one
      #                      descending from one of the four plugin base classes
      #                      (e.g., `LogStash::Inputs::Base`)
      # @return [void]
      def self.included(base)
        fail(ArgumentError, "`#{base}` must inherit LogStash::Plugin") unless base < LogStash::Plugin
      end

      ##
      # Unambiguously extracts the value of a param that may be provided with one or more deprecated params
      #
      # The `value_transformer` block is used when one or more deprecated params are explicitly provided,
      # to transform their effective values into a single suitable value for use as-if it had been
      # provided by the preferred param.
      # It is required except in the case of simple param renames.
      #
      # @param preferred_param [String]: the preferred param name
      # @param deprecated_params [String...]: the deprecated param names
      # @yield values_from_deprecated_params [Object...]: the ordered, validated-and-transformed values of _all_
      #                                                   deprecated params, including default values.
      # @yieldreturn [Object]: a single value to use as-if it had been provided by the preferred param
      #
      # @raise `LogStash::ConfigurationError` if both preferred and deprecated params are explicitly provided
      # @return [Object]: the value of the preferred param or an equivalent derived from provided deprecated params
      #
      # @note Relies on upstream deprecation warnings, and does not emit its own
      def config_with_deprecated_target!(preferred_param, *deprecated_params, &value_transformer)
        fail ArgumentError, 'preferred param name is required' if preferred_param.nil?
        fail ArgumentError, 'deprecated params names are required' if deprecated_params.empty?
        fail ArgumentError, 'block required for multiple deprecated params' if deprecated_params.size > 1 && !block_given?
        fail ArgumentError, 'transformer arity mismatch' if value_transformer && value_transformer.arity != deprecated_params.size
        validate_deprecated_params!(deprecated_params)

        provided_deprecated_params = original_params.keys.select { |k| deprecated_params.include?(k) }

        # If only the new param was set, return the value without apply any transformation
        return params.fetch(preferred_param, nil) unless provided_deprecated_params.any?

        # Both new and deprecated params were set
        if original_params.include?(preferred_param)
          deprecated_desc = "(deprecated) `#{provided_deprecated_params.join('`,`')}`"
          raise(LogStash::ConfigurationError, "Both `#{preferred_param}` and #{deprecated_desc} were set. Use only `#{preferred_param}`.")
        end

        # If no value transformer was provided, the value should already be on the expected format
        return params.fetch(deprecated_params.first) unless value_transformer

        value_transformer.call(*params.values_at(*deprecated_params))
      end

      private

      def validate_deprecated_params!(deprecated_params)
        deprecated_params.each do |dp|
          fail ArgumentError, "param `#{dp}` not marked deprecated" unless self.class.get_config.dig(dp, :deprecated)
        end
      end
    end
  end
end
