require 'concurrent'
require 'pstore'
require 'fileutils'

module Prometheus
  module Client
    module DataStores
      # Stores data in files, using the `PStore` data structure.
      # Even though PStores are thread and multi-process safe, it creates one separate
      # PStore per process and per thread, to reduce contention to a minimum.
      #
      # On calling `all_values` for a Metric, it'll find all files that apply, and collate
      # them together.
      #
      # In order to do this, each Metric needs an `:aggregation` setting, specifying how
      # to aggregate the multiple possible values we can get for each labelset. By default,
      # they are `SUM`med, which is what most use cases call for (counters and histograms,
      # for example).
      # However, for Gauges, it's possible to require `MAX` or `MIN` as aggregation, to get
      # the highest value of all the processes / threads
      class Pstore
        class InvalidStoreSettingsError < StandardError; end
        AGGREGATION_MODES = [MAX = :max, MIN = :min, SUM = :sum]
        DEFAULT_METRIC_SETTINGS = { aggregation: SUM }

        def initialize(dir:)
          @store_settings = { dir: dir }
          FileUtils.mkdir_p(dir)
        end

        def for_metric(metric_name, metric_type:, metric_settings: {})
          settings = DEFAULT_METRIC_SETTINGS.merge(metric_settings)
          validate_metric_settings(settings)

          MetricStore.new(metric_name: metric_name,
                          store_settings: @store_settings,
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
          attr_reader :metric_name, :store_settings

          def initialize(metric_name:, store_settings:, metric_settings:)
            @metric_name = metric_name
            @store_settings = store_settings
            @values_aggregation_mode = metric_settings[:aggregation]

            @in_transaction = {} # This horror is explained on `synchronize`

            # We'll have one PStore per thread, this hash is indexed by the thread's ObjectID
            @internal_stores = {}
          end

          # PStores don't support nested transactions. However, using a transaction on the
          # file is the only way we can guarantee multiple values get incremented together.
          # Otherwise, if we do a transaction on each increment, and we have another Lock
          # primitive here, some other process could read half-committed, inconsistent
          # Histogram buckets.
          #
          # This guarantees that that won't happen, and allows us to have "nested"
          # transactions through `synchronize`. It's horrible, but ¯\_(ツ)_/¯
          #
          # Under normal circumstances, doing this would NOT BE THREAD SAFE
          # However, since we have one separate store per thread, we don't really have
          # multiple threads accessing the same store, so as long as we keep track of
          # whether each thread is in a transaction, we're fine.
          def synchronize
            if @in_transaction[thread_id]
              yield
            else
              internal_store.transaction do
                @in_transaction[thread_id] = true
                result = yield
                @in_transaction[thread_id] = false
                result
              end
            end
          end

          def set(labels:, val:)
            synchronize do
              internal_store[labels] = val.to_f
            end
          end

          def increment(labels:, by: 1)
            synchronize do
              internal_store[labels] = internal_store.fetch(labels, 0.0) + by
            end
          end

          def get(labels:)
            synchronize do
              internal_store.fetch(labels, 0.0)
            end
          end

          def all_values
            stores_data = Hash.new{ |hash, key| hash[key] = [] }

            # There's no need to call `synchronize` here. We're opening a second handle to
            # our internal store (and to all other processes stores), the PStore locking
            # does the job for us
            stores_for_metric.each do |store_path|
              store = PStore.new(store_path)
              store.transaction(true) do
                store.roots.each do |label_set|
                  stores_data[label_set] << store[label_set]
                end
              end
            end

            # Aggregate all the different values for each label_set
            stores_data.each_with_object({}) do |(label_set, values), acc|
              acc[label_set] = aggregate_values(values)
            end
          end

          private

          # All filenames for all stores for this metric (one per process)
          def stores_for_metric
            Dir.glob(File.join(@store_settings[:dir], "metric_#{ metric_name }___*"))
          end

          def internal_store
            @internal_stores[thread_id] ||= PStore.new(pstore_filename)
          end

          # Filename for this metric's PStore (one per process)
          def pstore_filename
            filename = "metric_#{ metric_name }___#{ process_id }___#{ thread_id }.pstore"
            File.join(@store_settings[:dir], filename)
          end

          def process_id
            Process.pid
          end

          def thread_id
            Thread.current.object_id
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
