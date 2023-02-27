# encoding: utf-8

require 'rspec/its'

require "logstash-core"
require 'logstash/inputs/base'
require 'logstash/filters/base'
require 'logstash/codecs/base'
require 'logstash/outputs/base'

require "logstash/plugin_mixins/normalize_config_support"

describe LogStash::PluginMixins::NormalizeConfigSupport do

  let(:normalize_config_support) { described_class }
  let(:options) { {} }

  class PluginClass < LogStash::Outputs::Base
    include LogStash::PluginMixins::NormalizeConfigSupport
    config_name "plugin_class"
    config :list_config, :list => true, :default => %w[one two]
    config :new_config, :validate => :string
    config :new_config_with_default, :validate => :string, :default => "default"
    config :deprecated_config, :validate => :string, :deprecated => "deprecated config"
    config :another_deprecated_config, :validate => :string, :deprecated => "other deprecated config"
    config :another_config, :validate => :string

    def initialize(*params)
      super
    end
  end

  subject { PluginClass::new(options) }

  context 'included into a class' do
    context 'that does not inherit from `LogStash::Plugin`' do
      let(:plugin_class) { Class.new }
      it 'fails with an ArgumentError' do
        expect do
          plugin_class.send(:include, normalize_config_support)
        end.to raise_error(ArgumentError, /LogStash::Plugin/)
      end
    end
  end

  context 'normalize_config' do
    it 'should fail if canonical config is nil' do
      expect {
        subject.normalize_config(nil) do |_|
        end
      }.to raise_error(ArgumentError, /`canonical_config` is required/)
    end

    it 'should fail if canonical config does not exists' do
      expect {
        subject.normalize_config('unknown_config') do |_|
        end
      }.to raise_error(ArgumentError, /Config `unknown_config` does not exists/)

      expect {
        subject.normalize_config(:unknown_config) do |_|
        end
      }.to raise_error(ArgumentError, /Config `unknown_config` does not exists/)
    end

    it 'should fail if configurator block is not given' do
      expect { subject.normalize_config('unknown_config') }.to raise_error(ArgumentError, /`configurator` is required/)
    end

    context 'configurator' do
      context 'with deprecated mapping' do
        it 'should fail if deprecated params are empty' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping do |_|
              end
            end
          }.to raise_error(ArgumentError, /`deprecated_params` cannot be empty/)
        end

        it 'should fail if no value transformer is given' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config')
            end
          }.to raise_error(ArgumentError, /`value_transformer` is required/)
        end

        it 'should fail if value transformer arity mismatch' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config') do |_|
                "foo"
              end
            end
          }.to_not raise_error

          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config', 'another_deprecated_config') do |_|
                "foo"
              end
            end
          }.to raise_error(ArgumentError, /`value_transformer` arity mismatch the number of deprecated params/)

          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config') do |deprecated_config, _|
                'foo'
              end
            end
          }.to raise_error(ArgumentError, /`value_transformer` arity mismatch the number of deprecated params/)
        end

        it 'should fail if called more than once' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config') do |_|
              end
              normalizer.with_deprecated_mapping('another_deprecated_config') do |_|
              end
            end
          }.to raise_error(RuntimeError, /Deprecated mappings already configured for this config normalizer/)
        end
      end

      context 'with deprecated alias' do
        let(:options) { { 'new_config' => "new" } }

        it 'should not transform the value' do
          final_value = subject.normalize_config('new_config') do |normalizer|
            normalizer.with_deprecated_alias('deprecated_config') do |_|
              raise 'Should be ignored'
            end
          end

          expect(final_value).to be_eql('new')
        end
      end
    end

    context 'value' do
      context 'when no deprecated mappings are configured' do
        let(:options) { { 'new_config' => "new" } }

        it 'should fail' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
            end
          }.to raise_error(RuntimeError, /No deprecated mappings configured for this config normalizer/)
        end
      end

      context 'when only the canonical config is supplied' do
        let(:options) { { 'new_config' => "new" } }

        it 'should be the canonical config value' do
          final_value = subject.normalize_config('new_config') do |normalizer|
            normalizer.with_deprecated_mapping('deprecated_config') do |deprecated_config|
              "new"
            end
          end

          expect(final_value).to be_eql('new')
        end
      end

      context 'when only deprecated params are supplied' do
        let(:options) { { 'deprecated_config' => 'one', 'another_deprecated_config' => 'two' } }

        it 'should be the transformed param value' do
          final_value = subject.normalize_config('new_config_with_default') do |normalizer|
            normalizer.with_deprecated_mapping('deprecated_config', 'another_deprecated_config') do |deprecated_config, other_deprecated_config|
              deprecated_config + other_deprecated_config
            end
          end

          expect(final_value).to be_eql('onetwo')
        end
      end

      context 'when both canonical and deprecated params are supplied' do
        let(:options) { { 'new_config' => "new", 'deprecated_config' => "old" } }

        it 'should raise a configuration error' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_deprecated_mapping('deprecated_config') do |deprecated_config|
                deprecated_config
              end
            end
          }.to raise_error(LogStash::ConfigurationError, /Both `new_config` and \(deprecated\) `deprecated_config` were set\. Use only `new_config`/)
        end
      end
    end
  end
end