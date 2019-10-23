require 'benchmark/ips'
require 'yaml'
require 'cgi'
require 'uri'
require 'rack'
require 'json'

LABELSET = { foo: "bar", xxx: "yyy", __pid: 12345 }

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)

  x.report("each with to_s") do
    h = {}
    LABELSET.each{ |k,v| h[k] = v.to_s }
  end

  x.report("each with NOOP") do
    h = {}
    LABELSET.each{ |k,v| h[k] = v }
  end

  x.report("each with String()") do
    h = {}
    LABELSET.each{ |k,v| h[k] = String(v) }
  end

  x.compare!
end

