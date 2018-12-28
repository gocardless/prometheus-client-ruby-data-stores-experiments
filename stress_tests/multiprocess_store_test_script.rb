require 'prometheus/client'
require 'prometheus/client/counter'
require 'prometheus/client/histogram'
require 'prometheus/client/data_stores/mmap_store'


SSD_TMP_DIR = "/tmp/prometheus_test_script"
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::MmapStore.new(dir: SSD_TMP_DIR)

LABELSETS = [
  { foo: "bar", path: "/something"},
  { foo: "bar", path: "/something_else"},
  { foo: "bar", path: "/404"},
  { foo: "baz", path: "/something"},
  { foo: "baz", path: "500"},
]

METRICS = [
  Prometheus::Client.registry.counter(
    "counter1".to_sym,
    docstring: "Counter 1",
    labels: LABELSETS.first.keys
  ),
  Prometheus::Client.registry.counter(
    "counter2".to_sym,
    docstring: "Counter 2",
    labels: LABELSETS.first.keys
  ),
  Prometheus::Client.registry.histogram(
    "histogram1".to_sym,
    docstring: "Histogram 1",
    labels: LABELSETS.first.keys
  )
]

# Incrementer process
#----------------------------------------------------------------
def increment_counters
  random = Random.new

  t1 = Thread.new do
    while true
      metric = METRICS.sample
      labelset = LABELSETS.sample

      if metric.type == :counter
        metric.increment(labels: labelset)
      else
        metric.observe(random.rand * 12, labels: labelset)
      end
    end
  end

  while true
    puts "Press Enter for stats"
    STDIN.gets
    3.times { puts "=" * 80 }
    METRICS.each do |metric|
      puts metric.name
      LABELSETS.each do |labelset|
        puts "#{labelset.inspect}: #{ metric.get(labels: labelset) }"
      end
      puts ""
    end
  end
end

def observe_counters
  while true
    puts "Press Enter for total counters"
    STDIN.gets
    3.times { puts "=" * 80 }
    METRICS.each do |metric|
      puts metric.name
      values = metric.values
      values.each do |labelset,v|
        puts "#{labelset.inspect}: #{ v }"
      end
      puts ""
    end
  end
end

if ARGV[0] == "increment"
  increment_counters
elsif ARGV[0] == "observe"
  observe_counters
else
  puts "Must add either increment or observe command"
end
