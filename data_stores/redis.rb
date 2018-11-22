require 'concurrent'

module Prometheus
  module Client
    module DataStores
      # Stores data in Redis, as a simple way of getting a shared piece of memory between
      # processes.
      # This store is useful to deal with pre-fork servers and other "multi-process"
      # scenarios where processes need to have access to each other's metrics data.
      #
      # IMPORTANT NOTE!!! You must have a local Redis server in each of your boxes where
      # you run this store.
      # Do not use a shared Redis server for all your servers. On the one hand, the network
      # roundtrip is going to be outrageously slow, and on the other, metrics between
      # your different servers would get conflated into one, giving invalid results.
      #
      # If you can't have each box have their own local Redis server, you may want to use
      # Pstore instead.
      #
      # Alternatively, if a shared Redis box is the only possible option for some reason,
      # and you're willing to accept the performance hit from it, you'd need to modify this
      # store to add a "server_id" to the keys stored in Redis, and somehow set that prefix
      # to be unique to each server. Or something similar to that. Make sure to benchmark
      # this against the Pstore to make sure it's actually the best route.
      #
      # It's also important to note that Redis is somewhat lossy when it comes to tiny
      # floats. The `spec/prometheus/client/formats/text_spec.rb` test fails if set to use
      # this store, because it sets `1.23e-45` as a value for a counter, and Redis
      # returns 0. This is documented in Redis, it only outputs 17 digits of precision
      # (https://redis.io/commands/incrbyfloat).
      # In most cases this should not be a problem, but if your metrics include tiny floats,
      # this store won't work as-is.
      #
      # When exporting metrics, the process that gets scraped by Prometheus will get the
      # values for each process, and aggregate them (generally that means SUMming the
      # values for each labelset).
      #
      # In order to do this, each Metric needs an `:aggregation` setting, specifying how
      # to aggregate the multiple possible values we can get for each labelset. By default,
      # they are `SUM`med, which is what most use cases call for (counters and histograms,
      # for example).
      # However, for Gauges, it's possible to set `MAX` or `MIN` as aggregation, to get
      # the highest value of all the processes / threads.
      #
      # When storing values in Redis, each process will have their own key. While it would
      # be great to just have one key for all processes, and take advantage of INCR to
      # always have the total value, which would be perfect for Counters and Histograms,
      # we still need to keep separate values for Gauges, to be able to compute the MAX/MIN
      # if that's what the user needs.
      #
      # The code could be modified so that this extra label is only added if the aggregation
      # mode is not SUM. However, this makes the code more complex for little actual gain.
      class Redis
        class InvalidStoreSettingsError < StandardError; end
        AGGREGATION_MODES = [MAX = :max, MIN = :min, SUM = :sum]
        DEFAULT_METRIC_SETTINGS = { aggregation: SUM }

        def initialize(connection_pool:)
          @connection_pool = connection_pool
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          settings = DEFAULT_METRIC_SETTINGS.merge(metric_settings)
          validate_metric_settings(settings)

          MetricStore.new(metric_name: metric_name,
                          connection_pool: @connection_pool,
                          metric_settings: settings)
        end

        private

        def validate_metric_settings(metric_settings)
          unless metric_settings.has_key?(:aggregation) &&
            AGGREGATION_MODES.include?(metric_settings[:aggregation])
            raise InvalidStoreSettingsError,
                  "Metrics need a valid :aggregation key"
          end

          unless (metric_settings.keys - [:aggregation]).empty?
            raise InvalidStoreSettingsError,
                  "Only :aggregation setting can be specified"
          end
        end

        class MetricStore
          attr_reader :metric_name, :connection_pool

          def initialize(metric_name:, connection_pool:, metric_settings:)
            @metric_name = metric_name
            @connection_pool = connection_pool
            @values_aggregation_mode = metric_settings[:aggregation]
          end

          def synchronize
            connection_pool.with do |conn|
              conn.pipelined do
                yield # this will checkout a connection again. That's fine, it'll be the same connection
              end
            end
          end

          def set(labels:, val:)
            connection_pool.with do |conn|
              conn.hset(redis_key, hash_key(labels), val)
            end
          end

          def increment(labels:, by: 1)
            connection_pool.with do |conn|
              conn.hincrbyfloat(redis_key, hash_key(labels), by)
            end
          end

          def get(labels:)
            connection_pool.with do |conn|
              conn.hget(redis_key, hash_key(labels)).to_f
            end
          end

          def all_values
            raw_redis = connection_pool.with do |conn|
              conn.hgetall(redis_key)
            end

            labelset_data = raw_redis.each_with_object({}) do |(labels_qs, v), acc|
              # Labels come as a query string, and CGI::parse returns arrays for each key
              # "foo=bar&x=y" => { "foo" => ["bar"], "x" => ["y"] }
              # Turn the keys back into symbols, and remove the arrays
              labels = CGI::parse(labels_qs).map do |k, vs|
                [k.to_sym, vs.first]
              end.to_h

              label_set = labels.reject { |k,_| k == :__pid }
              acc[label_set] ||= []
              acc[label_set] << v.to_f # Value comes back from redis as String
            end

            # Aggregate all the different values for each label_set
            labelset_data.each_with_object({}) do |(label_set, values), acc|
              acc[label_set] = aggregate_values(values)
            end
          end

          private

          def redis_key
            @redis_key ||= "metric_#{ metric_name }"
          end

          def hash_key(labels)
            key = labels.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
            key << "&__pid=" << process_id.to_s
          end

          def process_id
            Process.pid
          end

          def aggregate_values(values)
            if @values_aggregation_mode == SUM
              values.inject { |sum, element| sum + element }
            elsif @values_aggregation_mode == MAX
              values.max
            elsif @values_aggregation_mode == MIN
              values.min
            else
              raise InvalidStoreSettingsError,
                    "Invalid Aggregation Mode: #{ @values_aggregation_mode }"
            end
          end
        end

        private_constant :MetricStore
      end
    end
  end
end
