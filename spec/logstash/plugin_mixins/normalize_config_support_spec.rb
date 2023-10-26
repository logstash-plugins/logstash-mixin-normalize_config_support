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
    config :another_new_config, :validate => :string
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
          }.to raise_error(ArgumentError, /Deprecated mappings already configured for this config normalizer/)
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

      context 'with required aliases' do
        it 'should fail if required alias are empty' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_required_aliases
            end
          }.to raise_error(ArgumentError, /`required_aliases` cannot be empty/)
        end

        it 'should fail if called more than once' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_required_aliases('another_config')
              normalizer.with_required_aliases('another_config')
            end
          }.to raise_error(ArgumentError, /Required aliases mappings already configured for this config normalizer/)
        end

        it 'should fail if required aliases includes canonical config' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_required_aliases('new_config', 'non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Canonical config cannot be mapped as a required alias/)
        end

        it 'should fail if alias does not exists' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_required_aliases('non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Config `non_existing_alias` does not exists/)
        end
      end

      context 'with dependent aliases' do
        it 'should fail if dependent alias are empty' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_dependent_aliases
            end
          }.to raise_error(ArgumentError, /`dependent_aliases` cannot be empty/)
        end

        it 'should fail if called more than once' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_dependent_aliases('another_config')
              normalizer.with_dependent_aliases('another_config')
            end
          }.to raise_error(ArgumentError, /Dependent aliases mappings already configured for this config normalizer/)
        end

        it 'should fail if dependent aliases includes canonical config' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_dependent_aliases('new_config', 'non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Canonical config cannot be mapped as a dependent alias/)
        end

        it 'should fail if alias does not exists' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_dependent_aliases('non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Config `non_existing_alias` does not exists/)
        end
      end

      context 'with conflicting aliases' do
        it 'should fail if conflicting alias are empty' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_conflicting_aliases
            end
          }.to raise_error(ArgumentError, /`conflicting_aliases` cannot be empty/)
        end

        it 'should fail if called more than once' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_conflicting_aliases('another_config')
              normalizer.with_conflicting_aliases('another_config')
            end
          }.to raise_error(ArgumentError, /Conflicting aliases mappings already configured for this config normalizer/)
        end

        it 'should fail if conflicting aliases includes canonical config' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_conflicting_aliases('new_config', 'non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Canonical config cannot be mapped as a conflicting alias/)
        end

        it 'should fail if alias does not exists' do
          expect {
            subject.normalize_config('new_config') do |normalizer|
              normalizer.with_conflicting_aliases('non_existing_alias')
            end
          }.to raise_error(ArgumentError, /Config `non_existing_alias` does not exists/)
        end
      end
    end

    context 'value' do
      context 'when no mappings are configured' do
        let(:options) { { 'new_config' => "new" } }

        it 'should return the config value' do
          final_value = subject.normalize_config('new_config') do |normalizer|
          end

          expect(final_value).to be_eql('new')
        end
      end

      context "with required config" do
        context "when required config value is provided" do
          let(:options) { { "new_config" => "new", "another_config" => "other" } }
          it "should not fail" do
            final_value = subject.normalize_config('new_config') do |normalizer|
              normalizer.with_required_aliases(:another_config)
            end

            expect(final_value).to be_eql('new')
          end
        end

        context "when both canonical and required config are not provided" do
          let(:options) { { } }
          it "should not fail" do
            expect {
              subject.normalize_config('new_config') do |normalizer|
                normalizer.with_required_aliases(:new_config_with_default)
              end
            }.to_not raise_error
          end
        end

        context "when required config has a default value" do
          let(:options) { { "new_config" => "none"} }

          it "should not fail" do
            expect {
            subject.normalize_config("new_config") do |normalizer|
              normalizer.with_required_aliases(:new_config_with_default)
            end
            }.to_not raise_error
          end
        end

        context "when required config value is not provided" do
          let(:options) { { "new_config" => "new" } }

          it "should raise a configuration error for single missing value" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_required_aliases(:another_config)
              end
            }.to raise_error(LogStash::ConfigurationError, /Config `new_config` requires `another_config` to be set/)
          end

          it "should raise a configuration error for multiple missing values" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_required_aliases(:another_config, :another_new_config)
              end
            }.to raise_error(LogStash::ConfigurationError, /Config `new_config` requires `another_config`, `another_new_config` to be set/)
          end
        end
      end

      context "with dependent configs" do
        context "when canonical and dependent config values are provided" do
          let(:options) { { "new_config" => "new", "another_config" => "other" } }

          it "should not fail" do
            final_value = subject.normalize_config("new_config") do |normalizer|
              normalizer.with_dependent_aliases("another_config")
            end

            expect(final_value).to be_eql('new')
          end
        end

        context "when both canonical and dependent configs values are not provided" do
          let(:options) { { } }
          it "should not fail" do
            expect {
              subject.normalize_config(:new_config) do |normalizer|
                normalizer.with_dependent_aliases(:another_config)
              end
            }.to_not raise_error
          end
        end

        context "when canonical config has a default value and only a dependent alias is provided" do
          let(:options) { { "another_config" => "another" } }
          it "should not fail" do
            expect {
              subject.normalize_config(:new_config_with_default) do |normalizer|
                normalizer.with_dependent_aliases(:another_config)
              end
            }.to_not raise_error
          end
        end

        context "when no canonical config value is provided" do
          let(:options) { { "another_config" => "another_value", "another_new_config" => "new" } }

          it "should fail for single dependent alias value" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_dependent_aliases("another_config")
              end
            }.to raise_error(LogStash::ConfigurationError, /Configs `another_config` requires `new_config` to be set/)
          end

          it "should fail for multiple dependent aliases values" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_dependent_aliases(:another_config, :another_new_config)
              end
            }.to raise_error(LogStash::ConfigurationError, /Configs `another_config`, `another_new_config` requires `new_config` to be set/)
          end

          it "should fail for multiple dependent aliases config with single value provided" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_dependent_aliases(:deprecated_config, :another_new_config)
              end
            }.to raise_error(LogStash::ConfigurationError, /Configs `another_new_config` requires `new_config` to be set/)
          end
        end

        context "combined with deprecated mapping normalizer" do
          let(:options) { { "deprecated_config" => "deprecated_config_value" } }

          it "should return the transformed value" do
            final_value = subject.normalize_config("new_config") do |normalizer|
              normalizer.with_deprecated_mapping("deprecated_config") do |deprecated_config|
                "transformed_value"
              end

              normalizer.with_dependent_aliases(:another_config)
            end

            expect(final_value).to be_eql("transformed_value")
          end
        end
      end

      context "with conflicting configs" do
        context "when only the canonical config value is provided" do
          let(:options) { { "new_config" => "new_config_value" } }

          it "should not fail" do
            final_value = subject.normalize_config("new_config") do |normalizer|
              normalizer.with_conflicting_aliases("another_config")
            end

            expect(final_value).to be_eql('new_config_value')
          end
        end

        context "when both canonical and conflicting configs are not provided" do
          let(:options) { { "new_config" => "new", "another_config" => "another", "another_new_config" => "another_new" } }

          it "should fail for single conflicting alias value" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_conflicting_aliases("another_new_config")
              end
            }.to raise_error(LogStash::ConfigurationError, /Use either `new_config` or `another_new_config`/)
          end

          it "should fail for multiple conflicting aliases values" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_conflicting_aliases(:another_config, :another_new_config)
              end
            }.to raise_error(LogStash::ConfigurationError, /Use either `new_config` or `another_config`, `another_new_config`/)
          end

          it "should fail for multiple conflicting aliases config with single value provided" do
            expect {
              subject.normalize_config("new_config") do |normalizer|
                normalizer.with_conflicting_aliases(:another_config, :new_config_with_default)
              end
            }.to raise_error(LogStash::ConfigurationError, /Use either `new_config` or `another_config`/)
          end
        end

        context "combined with deprecated normalizer" do
          let(:options) { { "deprecated_config" => "deprecated_config_value" } }

          it "should return the transformed value" do
            final_value = subject.normalize_config("another_config") do |normalizer|
              normalizer.with_deprecated_mapping("deprecated_config") do |deprecated_config|
                "transformed_value"
              end

              normalizer.with_conflicting_aliases(:new_config)
            end

            expect(final_value).to be_eql("transformed_value")
          end
        end
      end

      context "with config deprecations" do
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
end