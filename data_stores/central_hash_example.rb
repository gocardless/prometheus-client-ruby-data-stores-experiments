require 'concurrent'

module Prometheus
  module Client
    module DataStores
      # Stores all the data in a simple, synchronized global Hash
      #
      # This was just a proof of concept of the Store interface, this store is really
      # slow because of all the label merging, and there's no reason to do this if we're
      # using `Hash` as its backing.
      class CentralHashExample
        class InvalidStoreSettingsError < StandardError; end

        attr_reader :internal_store

        def initialize
          @internal_store = Hash.new { |hash, key| hash[key] = 0.0 }
          @rwlock = Concurrent::ReentrantReadWriteLock.new
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          # We don't need `metric_type` or `metric_settings` for this particular store
          validate_metric_settings(metric_settings: metric_settings)
          MetricStore.new(store: self, metric_name: metric_name)
        end

        def synchronize
          @rwlock.with_write_lock { yield }
        end

        private

        def validate_metric_settings(metric_settings:)
          unless metric_settings.empty?
            raise InvalidStoreSettingsError,
                  "CentralHashExample doesn't allow any metric_settings"
          end
        end

        class MetricStore
          def initialize(store:, metric_name:)
            @store = store
            @internal_store = store.internal_store
            @metric_name = metric_name
          end

          def synchronize
            @store.synchronize { yield }
          end

          def set(labels:, val:)
            synchronize do
              @internal_store[store_key(labels)] = val.to_f
            end
          end

          def increment(labels:, by: 1)
            synchronize do
              @internal_store[store_key(labels)] += by
            end
          end

          def get(labels:)
            synchronize do
              @internal_store[store_key(labels)]
            end
          end

          def all_values
            store_copy = synchronize { @internal_store.dup }

            store_copy.each_with_object({}) do |(labels, v), acc|
              if labels["__metric_name"] == @metric_name
                label_set = labels.reject { |k,_| k == "__metric_name" }
                acc[label_set] = v
              end
            end
          end

          private

          def store_key(labels)
            labels.merge(
              { "__metric_name" => @metric_name }
            )
          end
        end

        private_constant :MetricStore
      end
    end
  end
end
