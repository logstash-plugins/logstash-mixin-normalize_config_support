# encoding: utf-8

require 'rspec/its'

require "logstash-core"
require 'logstash/inputs/base'
require 'logstash/filters/base'
require 'logstash/codecs/base'
require 'logstash/outputs/base'

require "logstash/plugin_mixins/config_deprecation_support"

describe LogStash::PluginMixins::ConfigDeprecationSupport do

  let(:config_deprecation_support) { described_class }
  let(:options) { {} }

  class PluginClass < LogStash::Outputs::Base
    include LogStash::PluginMixins::ConfigDeprecationSupport
    config_name "plugin_class"
    config :list_config, :list => true, :default => %w[one two]
    config :new_config, :validate => :string
    config :new_config_with_default, :validate => :string, :default => "default"
    config :deprecated_config, :validate => :string, :deprecated => "deprecated config"
    config :other_deprecated_config, :validate => :string, :deprecated => "other deprecated config"
    config :other_config, :validate => :string

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
          plugin_class.send(:include, config_deprecation_support)
        end.to raise_error(ArgumentError, /LogStash::Plugin/)
      end
    end
  end

  context 'config with deprecated value' do
    it 'should fail if param name is nil' do
      expect { subject.config_with_deprecated_value!(nil) }.to raise_error(ArgumentError, /param name is required/)
    end

    it 'should fail if block is not given' do
      expect { subject.config_with_deprecated_value!("foo") }.to raise_error(ArgumentError, /block is required/)
    end

    it 'should fail if value transformer arity mismatch' do
      expect {
        subject.config_with_deprecated_value!("foo") do |one|
          one
        end
      }.to_not raise_error

      expect {
        subject.config_with_deprecated_value!("foo") do |one, two|
          one + two
        end
      }.to raise_error(ArgumentError, /transformer arity mismatch/)

      expect {
        subject.config_with_deprecated_value!("foo") do ||

        end
      }.to raise_error(ArgumentError, /transformer arity mismatch/)
    end

    it 'should fail if comparator arity mismatch' do
      expect {
        subject.config_with_deprecated_value!("foo", -> (one, two) {}) do |value|
          value
        end
      }.to_not raise_error

      expect {
        subject.config_with_deprecated_value!("foo", -> (one, two, too_much) {}) do |value|
          value
        end
      }.to raise_error(ArgumentError, /comparator arity mismatch/)

      expect {
        subject.config_with_deprecated_value!("foo", -> not_enough {}) do |value|
          value
        end
      }.to raise_error(ArgumentError, /comparator arity mismatch/)
    end

    context 'transformation' do
      let(:options) { { 'other_config' => "ping" } }

      it 'should transform value if config is set with a deprecated value' do
        final_value = subject.config_with_deprecated_value!('other_config') do |value|
          if value == "ping"
            "pong"
          else
            value
          end
        end

        expect(final_value).to be_eql("pong")
      end

      it 'should use transformed value' do
        final_value = subject.config_with_deprecated_value!('other_config') do |value|
          value
        end

        expect(final_value).to be_eql("ping")
      end

      it 'should transform default param value' do
        final_value = subject.config_with_deprecated_value!('new_config_with_default') do |value|
          value
        end

        expect(final_value).to be_eql("default")
      end

      it 'should use equality comparator' do
        expect(subject).to receive(:deprecation_logger_enabled?).and_return(true)
        expect(subject.deprecation_logger).to_not receive(:deprecated)

        subject.config_with_deprecated_value!('list_config', -> value, transformed_value{
          value == transformed_value.sort
        }) do |list_config|
          list_config.dup.reverse
        end
      end

      it 'should log deprecation if value was transformed' do
        expect(subject).to receive(:deprecation_logger_enabled?).and_return(true)
        expect(subject.deprecation_logger).to receive(:deprecated).with(/Value `ping` for config `other_config` is deprecated, please use `pong` instead/)

        subject.config_with_deprecated_value!('other_config') do |value|
          "pong"
        end
      end

      it 'should not log deprecation if value was not transformed' do
        expect(subject).to receive(:deprecation_logger_enabled?).and_return(true)
        expect(subject.deprecation_logger).to_not receive(:deprecated)

        subject.config_with_deprecated_value!('other_config') do |value|
          value
        end
      end
    end
  end

  context 'config with deprecated target' do
    it 'should fail if preferred param is nil' do
      expect { subject.config_with_deprecated_target!(nil) }.to raise_error(ArgumentError, /preferred param name is required/)
    end

    it 'should fail if deprecated params is empty' do
      expect { subject.config_with_deprecated_target!("deprecated_config") }.to raise_error(ArgumentError, /deprecated params names are required/)
    end

    it 'should fail with multiple deprecated params and no transformation block' do
      expect { subject.config_with_deprecated_target!("deprecated_config", "bar", "dummy") }.to raise_error(ArgumentError, /block required for multiple deprecated params/)
    end

    it 'should fail if value transformer arity mismatch' do
      expect {
        subject.config_with_deprecated_target!("foo", "deprecated_config") do |bar|
          bar
        end
      }.to_not raise_error

      expect {
        subject.config_with_deprecated_target!("foo", "bar") do |bar, two|
          bar
        end
      }.to raise_error(ArgumentError, /transformer arity mismatch/)

      expect {
        subject.config_with_deprecated_target!("foo", "bar") do ||
        end
      }.to raise_error(ArgumentError, /transformer arity mismatch/)
    end

    context "when only the preferred param is set" do
      let(:options) { { 'new_config' => "new" } }

      it 'should use the preferred param value' do
        final_value = subject.config_with_deprecated_target!("new_config", "deprecated_config") do |deprecated_config|
          raise "should not transform the value"
        end

        expect(final_value).to be_eql("new")
      end
    end

    context "when only the deprecated params are set" do
      let(:options) { { 'deprecated_config' => "one", "other_deprecated_config" => "two" } }

      it 'should use the transformed param value' do
        final_value = subject.config_with_deprecated_target!("new_config_with_default", "deprecated_config", "other_deprecated_config") do |deprecated_config, other_deprecated_config|
          deprecated_config + other_deprecated_config
        end

        expect(final_value).to be_eql("onetwo")
      end
    end

    context "when preferred and deprecated params are set" do
      let(:options) { { 'new_config' => "new", 'deprecated_config' => "old" } }

      it 'should raise a configuration error' do
        expect {
          subject.config_with_deprecated_target!("new_config", "deprecated_config") do |deprecated_config|
            deprecated_config
          end
        }.to raise_error(LogStash::ConfigurationError, /Both `new_config` and \(deprecated\) `deprecated_config` were set\. Use only `new_config`/)
      end
    end
  end
end