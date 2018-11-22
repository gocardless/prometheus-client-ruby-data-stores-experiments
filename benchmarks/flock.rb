require 'benchmark/ips'

FILENAME = "flockfile.txt"
File.open(FILENAME, 'w') {|f| f.write("xxx") }

f = File.new(FILENAME)

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)
  x.report("Flock") { f.flock(File::Constants::LOCK_EX) }
end
