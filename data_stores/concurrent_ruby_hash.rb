require 'concurrent'

# IMPORTANT NOTE!!!
# This store DOESN'T actually work!!!
# DO NOT USE!!!!
#
# The guarantees concurrent-ruby gives us are great, but you still can't do
#   ``@internal_store[labels] += by`
#
# I'm not exactly sure why, since that, on a built-in hash, in a normal vanilla threaded
# scenario actually ends up with the right numbers!
# But if you run this through the `data_stores` benchmark, it reports bad results.
module Prometheus
  module Client
    module DataStores
      # This store DOESN'T actually work!!!
      # DO NOT USE!!!!
      # 
      # Stores all the data in thread-safe hashes, one per metric.
      # These hashes automatically lock on every access, so we don't need to manually
      # deal with concurrency.
      #
      # In MRI, this is *almost* the same as the `SingleThreaded` store. You could *almost*
      # use `SingleThreaded` in a multi-threaded environment, as long as you're in MRI.
      #
      # The only difference is how metrics that need to update multiple values at once
      # will behave. If you use `SingleThreaded` in a multi-threaded environment, a scrape
      # may get inconsistent values for Histogram Buckets, since another thread may be in
      # the middle of updating those buckets.
      #
      # This store makes that use-case safe, and it also makes it safe in JRuby, RBX, etc.
      # In MRI, it has about the same performance characteristics as `SingleThreaded`
      # (because it's practically the same). If you're NOT on MRI, however, you probably
      # want to run the data stores benchmark to see how this behaves compared to
      # `SingleThreaded` and `Synchronized`
      #
      # This store DOESN'T actually work!!!
      # DO NOT USE!!!!
      class ConcurrentRubyHash
        class InvalidStoreSettingsError < StandardError; end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          # We don't need `metric_type` or `metric_settings` for this particular store
          validate_metric_settings(metric_settings: metric_settings)
          MetricStore.new
        end

        private

        def validate_metric_settings(metric_settings:)
          unless metric_settings.empty?
            raise InvalidStoreSettingsError,
                  "ConcurrentRubyHash doesn't allow any metric_settings"
          end
        end

        class MetricStore
          def initialize
            @internal_store = Concurrent::Hash.new { |hash, key| hash[key] = 0.0 }
            @rwlock = Concurrent::ReentrantReadWriteLock.new
          end

          # We still need this method, for when a metric wants to modify multiple values
          # atomically. For this reason, we also synchronize on `all_values`, since
          # otherwise we could export half-updated values
          def synchronize
            @rwlock.with_write_lock { yield }
          end

          def set(labels:, val:)
            @internal_store[labels] = val.to_f
          end

          def increment(labels:, by: 1)
            @internal_store[labels] += by
          end

          def get(labels:)
            @internal_store[labels]
          end

          def all_values
            synchronize { @internal_store.dup }
          end
        end

        private_constant :MetricStore
      end
    end
  end
end
