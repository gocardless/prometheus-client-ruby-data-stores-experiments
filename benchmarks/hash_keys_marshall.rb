require 'benchmark/ips'
require 'yaml'
require 'cgi'
require 'uri'
require 'rack'
require 'json'

LABELSET = { foo: "bar", xxx: "yyy", __pid: "12345" }

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)

  x.report("JSON") { LABELSET.to_json }

  x.report("YAML.dump") { YAML.dump(LABELSET) }

  x.report("Inspect") { LABELSET.inspect }

  x.report("Marshall.dump") { Marshal.dump(LABELSET) }

  x.report("each_with_object into array plus join") do
    LABELSET.each_with_object([]) { |(k,v), acc| acc << k << v }.join("|&%|")
  end

  x.report("to_a plus join") do
    LABELSET.to_a.join("|&%|")
  end

  x.report("each_with_object into string") do
    LABELSET.each_with_object("") { |(k,v), acc| acc << k.to_s << "|&%|" << v.to_s << "|&%|" }
  end

  x.report("map into unescaped querystring and join") do
    LABELSET.map{|k,v| "#{k}=#{v}"}.join('&')
  end

  x.report("map into escaped querystring and join") do
    LABELSET.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
  end

  x.report("URI.encode_www_form") do
    URI.encode_www_form(LABELSET)
  end

  x.report("Rack::Utils.build_query") do
    Rack::Utils.build_query(LABELSET)
  end

  x.report("flatten and join") do
    LABELSET.flatten.join("|&%|")
  end

  x.compare!
end


# Results:
#
#                                    JSON     287.735k (± 5.2%) i/s -      1.461M in   5.092600s
#                               YAML.dump      14.107k (± 3.1%) i/s -     70.750k in   5.020468s
#                                 Inspect     330.787k (± 2.8%) i/s -      1.661M in   5.026915s
#                           Marshall.dump     419.635k (± 1.5%) i/s -      2.099M in   5.003868s
#   each_with_object into array plus join     403.761k (± 2.4%) i/s -      2.042M in   5.061694s
#                          to_a plus join     411.944k (± 3.2%) i/s -      2.062M in   5.012157s
#            each_with_object into string     502.808k (± 2.3%) i/s -      2.545M in   5.063529s
# map into unescaped querystring and join     613.178k (± 2.6%) i/s -      3.100M in   5.059003s
#   map into escaped querystring and join     457.652k (± 2.0%) i/s -      2.302M in   5.031030s
#                     URI.encode_www_form     140.203k (± 5.2%) i/s -    703.934k in   5.033877s
#                 Rack::Utils.build_query     144.385k (± 4.9%) i/s -    722.260k in   5.014904s
#                        flatten and join     516.584k (± 2.4%) i/s -      2.606M in   5.048527s
#
# Comparison:
# map into unescaped querystring and join:   613178.1 i/s
# flatten and join:                          516584.1 i/s - 1.19x  slower
# each_with_object into string:              502807.8 i/s - 1.22x  slower
# map into escaped querystring and join:     457652.2 i/s - 1.34x  slower
# Marshall.dump:                             419634.9 i/s - 1.46x  slower
# to_a plus join:                            411943.6 i/s - 1.49x  slower
# each_with_object into array plus join:     403760.9 i/s - 1.52x  slower
# Inspect:                                   330787.1 i/s - 1.85x  slower
# JSON:                                      287735.2 i/s - 2.13x  slower
# Rack::Utils.build_query:                   144384.6 i/s - 4.25x  slower
# URI.encode_www_form:                       140203.1 i/s - 4.37x  slower
# YAML.dump:                                  14107.2 i/s - 43.47x  slower