require 'benchmark/ips'
require 'redis'
require 'connection_pool'

redis = Redis.new
pool = ConnectionPool.new(size: 5, timeout: 5) { Redis.new }

LABELSET = { foo: "bar", xxx: "yyy", __pid: "12345" }

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)

  x.report("SET") { redis.set("ips_set", 1.0) }
  x.report("INCR") { redis.incrby("ips_incrby", 1) }
  x.report("INCRBYFLOAT") { redis.incrbyfloat("ips_incrbyfloat", 1.0) }

  x.report("HSET") { redis.hset("ips_hset", "key", 1.0) }
  x.report("HINCR") { redis.hincrby("ips_hincrby", "key", 1) }
  x.report("HINCRBYFLOAT") { redis.hincrbyfloat("ips_hincrbyfloat", "key", 1.0) }

  # Semi-realistic call similar to what Metrics do, including serializing a Hash into
  # a string
  x.report("Metric") do
    key = LABELSET.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
    redis.hincrbyfloat("ips_mymetric", key , 1.0)
  end

  x.report "SET with ConnPool" do
    pool.with do |r|
      redis.set("ips_set", 1.0)
    end
  end

  x.compare!
end


# Results:
#
#                  SET     15.887k (± 1.8%) i/s -     79.815k in   5.025487s
#                 INCR     16.527k (± 1.5%) i/s -     83.616k in   5.060380s
#          INCRBYFLOAT     14.303k (± 3.0%) i/s -     72.852k in   5.098305s
#                 HSET     15.669k (± 1.9%) i/s -     79.447k in   5.072321s
#                HINCR     15.797k (± 1.6%) i/s -     78.988k in   5.001592s
#         HINCRBYFLOAT     13.527k (± 7.9%) i/s -     67.400k in   5.027152s
#               Metric     13.058k (± 2.5%) i/s -     66.300k in   5.080639s
#    SET with ConnPool     13.634k (± 2.1%) i/s -     69.212k in   5.078701s
#
# Comparison:
#                 INCR:    16527.3 i/s
#                  SET:    15887.0 i/s - 1.04x  slower
#                HINCR:    15796.5 i/s - 1.05x  slower
#                 HSET:    15668.6 i/s - 1.05x  slower
#          INCRBYFLOAT:    14303.4 i/s - 1.16x  slower
#    SET with ConnPool:    13634.1 i/s - 1.21x  slower
#         HINCRBYFLOAT:    13527.0 i/s - 1.22x  slower
#               Metric:    13058.3 i/s - 1.27x  slower
