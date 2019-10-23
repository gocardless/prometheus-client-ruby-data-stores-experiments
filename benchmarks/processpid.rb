require 'benchmark/ips'

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)

  x.report("Empty") { }
  x.report("Process PID") { Process.pid }
end
