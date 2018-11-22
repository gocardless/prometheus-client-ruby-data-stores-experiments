require 'concurrent'
require 'fileutils'
require "cgi"
require "mmap"

module Prometheus
  module Client
    module DataStores
      # WARNING!!!: This gem probably doesn't work in Ruby 2.1.
      # Read `data_stores/README.md` for more information!
      #
      # Also warning, this may or may not be stable, and may segfault on you.
      #
      # Stores data in Memory Mapped files, one file per process and per metric.
      #
      # Each process will get a file for a metric, and it will manage its contents through
      # an mmap (using the `mmap2` gem).
      #
      # When exporting metrics, the process that gets scraped by Prometheus  will find
      # all the files that apply to a metric, mmap into them, read their contents, and
      # aggregate them (generally that means SUMming the values for each labelset).
      #
      # In order to do this, each Metric needs an `:aggregation` setting, specifying how
      # to aggregate the multiple possible values we can get for each labelset. By default,
      # they are `SUM`med, which is what most use cases call for (counters and histograms,
      # for example).
      # However, for Gauges, it's possible to set `MAX` or `MIN` as aggregation, to get
      # the highest value of all the processes / threads.
      class MmapStore
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

            @rwlock = Concurrent::ReentrantReadWriteLock.new
          end

          # Synchronize is used to do a multi-process Mutex, when incrementing multiple
          # values at once, so that the other process, reading the file for export, doesn't
          # get incomplete increments.
          #
          # `in_process_sync`, instead, is just used so that two threads don't increment
          # the same value and get a context switch between read and write leading to an
          # inconsistency
          def synchronize
            in_process_sync do
              internal_store.with_file_lock do
                yield
              end
            end
          end

          def set(labels:, val:)
            in_process_sync do
              internal_store.write_value(store_key(labels), val.to_f)
            end
          end

          def increment(labels:, by: 1)
            key = store_key(labels)
            in_process_sync do
              value = internal_store.read_value(key)
              internal_store.write_value(key, value + by.to_f)
            end
          end

          def get(labels:)
            in_process_sync do
              internal_store.read_value(store_key(labels))
            end
          end

          def all_values
            stores_data = Hash.new{ |hash, key| hash[key] = [] }

            # There's no need to call `synchronize` here. We're opening a second handle to
            # the MMapped file, and `flock`ing it, which prevents inconsistent reads
            stores_for_metric.each do |mmap_path|
              begin
                store = MmapedDict.new(mmap_path)
                store.with_file_lock do
                  store.all_values.each do |(labelset_qs, v)|
                    # Labels come as a query string, and CGI::parse returns arrays for each key
                    # "foo=bar&x=y" => { "foo" => ["bar"], "x" => ["y"] }
                    # Turn the keys back into symbols, and remove the arrays
                    label_set = CGI::parse(labelset_qs).map do |k, vs|
                      [k.to_sym, vs.first]
                    end.to_h

                    stores_data[label_set] << v
                  end
                end
              ensure
                store.close
              end
            end

            # Aggregate all the different values for each label_set
            stores_data.each_with_object({}) do |(label_set, values), acc|
              acc[label_set] = aggregate_values(values)
            end
          end

          private

          def in_process_sync
            @rwlock.with_write_lock { yield }
          end

          def store_key(labels)
            labels.map{|k,v| "#{CGI::escape(k.to_s)}=#{CGI::escape(v.to_s)}"}.join('&')
          end

          def internal_store
            @internal_store ||= MmapedDict.new(mmap_filename)
          end

          # Filename for this metric's PStore (one per process)
          def mmap_filename
            filename = "metric_#{ metric_name }___#{ process_id }.mmap"
            File.join(@store_settings[:dir], filename)
          end

          def stores_for_metric
            Dir.glob(File.join(@store_settings[:dir], "metric_#{ metric_name }___*"))
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

        # A dict of doubles, backed by an mmapped file.
        #
        # The file starts with a 4 byte int, indicating how much of it is used.
        # Then 4 bytes of padding.
        # There's then a number of entries, consisting of a 4 byte int which is the
        # size of the next field, a utf-8 encoded string key, padding to an 8 byte
        # alignment, and then a 8 byte float which is the value.
        #
        # TODO(julius): dealing with Mmap.new, truncate etc. errors?
        class MmapedDict
          INITIAL_MMAP_SIZE = 1024*1024

          attr_reader :m, :capacity, :used, :positions

          def initialize(filename)
            @f = File.open(filename, 'a+b')
            if @f.size == 0
              @f.truncate(INITIAL_MMAP_SIZE)
            end
            @capacity = @f.size
            @m = Mmap.new(filename, 'rw', Mmap::MAP_SHARED)

            # Not using mlock because it requires CAP_IPC_LOCK which is usually not
            # available inside Docker containers. Also in our usage scenario, the
            # practice value of `mlock` is somewhat dubious.
            # @m.mlock

            @positions = {}
            @used = @m[0..3].unpack('l')[0]
            if @used == 0
              @used = 8
              @m[0..3] = [@used].pack('l')
            else
              read_all_values.each do |key, _, pos|
                @positions[key] = pos
              end
            end
          end

          # Yield (key, value, pos). No locking is performed.
          def all_values
            read_all_values.map { |k, v, p| [k, v] }
          end

          def read_value(key)
            if !@positions.has_key?(key)
              init_value(key)
            end

            pos = @positions[key]
            # We assume that reading from an 8 byte aligned value is atomic.
            @m[pos..pos + 7].unpack('d')[0]
          end

          def write_value(key, value)
            if !@positions.has_key?(key)
              init_value(key)
            end

            pos = @positions[key]
            # We assume that writing to an 8 byte aligned value is atomic.
            @m[pos..pos + 7] = [value].pack('d')
          end

          def close
            @m.msync
            @m.unmap
            @f.fsync
            @f.close
          end

          def with_file_lock
            @f.flock(File::LOCK_EX)
            yield
          ensure
            @f.flock(File::LOCK_UN)
          end

          private

          # Initialize a value. Lock must be held by caller.
          def init_value(key)
            # Pad to be 8-byte aligned.
            padded = key + (' ' * (8 - (key.length + 4) % 8))
            value = [key.length, padded, 0.0].pack("lA#{padded.length}d")
            while @used + value.length > @capacity
              @capacity = @m.extend(@capacity) # Double the size
            end
            @m[@used..@used + value.length] = value

            # Update how much space we've used.
            @used += value.length
            @m[0..3] = [@used].pack('l')
            @positions[key] = @used - 8
          end

          # Yield (key, value, pos). No locking is performed.
          def read_all_values
            pos = 8
            values = []
            while pos < @used
              encoded_len = @m[pos..(pos + 3)].unpack('l')[0]
              pos += 4
              encoded = @m[pos..(pos+encoded_len - 1)].unpack("A#{encoded_len}")[0]
              padded_len = encoded_len + (8 - (encoded_len + 4) % 8)
              pos += padded_len
              value = @m[pos..(pos + 7)].unpack('d')[0]
              values << [encoded, value, pos]
              pos += 8
            end
            values
          end
        end
      end
    end
  end
end


