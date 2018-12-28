require 'prometheus/client'
require 'prometheus/client/counter'
require 'prometheus/client/histogram'
require 'prometheus/client/data_stores/mmap_store'


SSD_TMP_DIR = "/tmp/prometheus_test_script"
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::MmapStore.new(dir: SSD_TMP_DIR)

METRIC =
  Prometheus::Client.registry.counter(
    "counter1".to_sym,
    docstring: "Counter 1",
    labels: [:foo]
  )

random = Random.new

t1 = Thread.new do
  i = 0
  while true
    i += 1
    labelset = { foo: i.to_s }
    METRIC.increment(labels: labelset)
  end
end

puts "PID: #{Process.pid}"
puts "Press Enter for stats"
while true
  STDIN.gets
  puts METRIC.values.keys.count
end


#
# store = Prometheus::Client::DataStores::MmapStore::MmapedDict.new("/tmp/prometheus_test_script/metric_counter1___42708.mmap")
#
# puts store.all_values.count
#