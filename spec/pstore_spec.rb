# encoding: UTF-8

require_relative '../data_stores/pstore'
require 'examples/data_store_example'

describe Prometheus::Client::DataStores::Pstore do
  subject { described_class.new(dir: "/tmp/prometheus_test") }
  let(:metric_store) { subject.for_metric(:metric_name, metric_type: :counter) }

  # Reset the PStores
  before do
    Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
  end

  it_behaves_like Prometheus::Client::DataStores

  it "only accepts valid :aggregation as Metric Settings" do
    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { aggregation: Prometheus::Client::DataStores::Pstore::SUM })
    end.not_to raise_error

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { aggregation: :invalid })
    end.to raise_error(Prometheus::Client::DataStores::Pstore::InvalidStoreSettingsError)

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { some_setting: true })
    end.to raise_error(Prometheus::Client::DataStores::Pstore::InvalidStoreSettingsError)
  end

  it "sums values from different processes" do
    metric_store1 = subject.for_metric(:metric_name, metric_type: :counter)
    allow(metric_store1).to receive(:process_id).and_return(12345)
    metric_store1.set(labels: { foo: "bar" }, val: 1)
    metric_store1.set(labels: { foo: "baz" }, val: 7)
    metric_store1.set(labels: { foo: "yyy" }, val: 3)

    metric_store2 = subject.for_metric(:metric_name, metric_type: :counter)
    allow(metric_store2).to receive(:process_id).and_return(23456)
    metric_store2.set(labels: { foo: "bar" }, val: 3)
    metric_store2.set(labels: { foo: "baz" }, val: 2)
    metric_store2.set(labels: { foo: "zzz" }, val: 1)

    expect(metric_store2.all_values).to eq(
      { foo: "bar" } => 4.0,
      { foo: "baz" } => 9.0,
      { foo: "yyy" } => 3.0,
      { foo: "zzz" } => 1.0,
    )

    # Both processes should return the same value
    expect(metric_store1.all_values).to eq(metric_store2.all_values)
  end

  context "with a metric that takes MAX instead of SUM" do
    it "reports the maximum values from different processes" do
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
      allow(metric_store1).to receive(:process_id).and_return(12345)
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
      allow(metric_store2).to receive(:process_id).and_return(23456)
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar" } => 3.0,
        { foo: "baz" } => 7.0,
        { foo: "yyy" } => 3.0,
        { foo: "zzz" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end

  context "with a metric that takes MIN instead of SUM" do
    it "reports the minimum values from different processes" do
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
      allow(metric_store1).to receive(:process_id).and_return(12345)
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
      allow(metric_store2).to receive(:process_id).and_return(23456)
      metric_store2.set(labels: { foo: "bar" }, val: 3)
      metric_store2.set(labels: { foo: "baz" }, val: 2)
      metric_store2.set(labels: { foo: "zzz" }, val: 1)

      expect(metric_store1.all_values).to eq(
        { foo: "bar" } => 1.0,
        { foo: "baz" } => 2.0,
        { foo: "yyy" } => 3.0,
        { foo: "zzz" } => 1.0,
      )

      # Both processes should return the same value
      expect(metric_store1.all_values).to eq(metric_store2.all_values)
    end
  end
end
