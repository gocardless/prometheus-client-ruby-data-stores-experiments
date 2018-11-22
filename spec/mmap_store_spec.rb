# encoding: UTF-8

ON_C_RUBY = (!defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby")

require_relative '../data_stores/mmap_store' if ON_C_RUBY
require 'examples/data_store_example'

ON_C_RUBY && describe(Prometheus::Client::DataStores::MmapStore) do
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
                         metric_settings: { aggregation: Prometheus::Client::DataStores::MmapStore::SUM })
    end.not_to raise_error

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { aggregation: :invalid })
    end.to raise_error(Prometheus::Client::DataStores::MmapStore::InvalidStoreSettingsError)

    expect do
      subject.for_metric(:metric_name,
                         metric_type: :counter,
                         metric_settings: { some_setting: true })
    end.to raise_error(Prometheus::Client::DataStores::MmapStore::InvalidStoreSettingsError)
  end

  it "raises when aggregating if we get to that that point with an invalid aggregation mode" do
    # This is basically just for coverage of a safety clause that can never be reached
    allow(subject).to receive(:validate_metric_settings) # turn off validation

    metric = subject.for_metric(:metric_name,
                                metric_type: :counter,
                                metric_settings: { aggregation: :invalid })
    metric.increment(labels: {}, by: 1)

    expect do
      metric.all_values
    end.to raise_error(Prometheus::Client::DataStores::MmapStore::InvalidStoreSettingsError)
  end

  it "sums values from different processes" do
    allow(Process).to receive(:pid).and_return(12345) # What could possible go wrong
    metric_store1 = subject.for_metric(:metric_name, metric_type: :counter)
    metric_store1.set(labels: { foo: "bar" }, val: 1)
    metric_store1.set(labels: { foo: "baz" }, val: 7)
    metric_store1.set(labels: { foo: "yyy" }, val: 3)

    allow(Process).to receive(:pid).and_return(23456) # What could possible go wrong
    metric_store2 = subject.for_metric(:metric_name, metric_type: :counter)
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
      allow(Process).to receive(:pid).and_return(12345) # What could possible go wrong
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456) # What could possible go wrong
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :max }
      )
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
      allow(Process).to receive(:pid).and_return(12345) # What could possible go wrong
      metric_store1 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
      metric_store1.set(labels: { foo: "bar" }, val: 1)
      metric_store1.set(labels: { foo: "baz" }, val: 7)
      metric_store1.set(labels: { foo: "yyy" }, val: 3)

      allow(Process).to receive(:pid).and_return(23456) # What could possible go wrong
      metric_store2 = subject.for_metric(
        :metric_name,
        metric_type: :gauge,
        metric_settings: { aggregation: :min }
      )
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

  it "resizes the MMap if metrics get too big" do
     truncate_calls_count = 0
     allow_any_instance_of(Mmap).
       to receive(:extend).and_wrap_original do |original_method, *args, &block|

       truncate_calls_count += 1
       original_method.call(*args, &block)
     end

    really_long_string = "a" * 500_000
    10.times do |i|
      metric_store.set(labels: { foo: "#{ really_long_string }#{ i }" }, val: 1)
    end

    expect(truncate_calls_count).to be >= 3
  end
end
