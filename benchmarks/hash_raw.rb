require 'benchmark/ips'

HASH_SINGLE = Hash.new { |hash, key| hash[key] = 0.0 }
HASH_SIMPLE = Hash.new { |hash, key| hash[key] = 0.0 }
HASH_OF_HASH_SINGLE = Hash.new { |hash, key| hash[key] = 0.0 }
HASH_OF_HASH_MULTIPLE = Hash.new { |hash, key| hash[key] = 0.0 }
HASH_OF_ARRAY_SINGLE = Hash.new { |hash, key| hash[key] = 0.0 }
HASH_OF_ARRAY_MULTIPLE = Hash.new { |hash, key| hash[key] = 0.0 }
BASE_LABELS = { foo: "bar" }
MUTEX = Mutex.new

simple_hash_index = 1
hash_of_hash_index = 1
hash_of_array_index = 1

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 1)

  x.report("Incrementing Single Constant Key") do
    HASH_SINGLE[:x] += 1
  end

  x.report("Incrementing Single Constant Key with a Mutex") do
    MUTEX.synchronize do
      HASH_SINGLE[:x] += 1
    end
  end

  x.report("Incrementing Many Constant Keys") do
    simple_hash_index = (simple_hash_index + 1) % 1000 # Only have 1000 keys
    HASH_SIMPLE[simple_hash_index] += 1
  end

  #------------------

  x.report("Incrementing Single Array Key") do
    HASH_OF_ARRAY_SINGLE[[0, 0, 0]] += 1
  end

  x.report("Incrementing Single Array Key with a Mutex") do
    MUTEX.synchronize do
      HASH_OF_ARRAY_SINGLE[[0, 0, 0]] += 1
    end
  end

  x.report("Incrementing Many Array Keys") do
    hash_of_array_index = (hash_of_array_index + 1) % 1000 # Only have 1000 keys
    key = [hash_of_array_index, hash_of_array_index, hash_of_array_index]
    HASH_OF_ARRAY_MULTIPLE[key] += 1
  end

  #------------------

  x.report("Incrementing Single Hash Key") do
    HASH_OF_HASH_SINGLE[{ foo: 0, bar: 0, baz: 0 }] += 1
  end

  x.report("Incrementing Single Hash Key with a Mutex") do
    MUTEX.synchronize do
      HASH_OF_HASH_SINGLE[{ foo: 0, bar: 0, baz: 0 }] += 1
    end
  end

  x.report("Incrementing Many Hash Keys") do
    hash_of_hash_index = (hash_of_hash_index + 1) % 1000 # Only have 1000 keys
    key = { foo: hash_of_hash_index, bar: hash_of_hash_index, baz: hash_of_hash_index }
    HASH_OF_HASH_MULTIPLE[key] += 1
  end

  x.compare!
end

# Results:
#
# Incrementing Single Constant Key                    6.630M (± 7.0%) i/s -     33.003M in   5.003051s
# Incrementing Single Constant Key with a Mutex       3.794M (± 7.4%) i/s -     18.941M in   5.024213s
# Incrementing Many Constant Keys                     4.751M (±10.4%) i/s -     23.496M in   5.010216s
# Incrementing Single Array Key                     404.191k (± 6.5%) i/s -      2.025M in   5.032005s
# Incrementing Single Array Key with a Mutex        369.171k (± 8.4%) i/s -      1.854M in   5.061934s
# Incrementing Many Array Keys                      392.789k (± 5.8%) i/s -      1.990M in   5.087344s
# Incrementing Single Hash Key                      236.976k (± 3.0%) i/s -      1.194M in   5.042470s
# Incrementing Single Hash Key with a Mutex         232.302k (± 2.9%) i/s -      1.164M in   5.015600s
# Incrementing Many Hash Keys                       213.523k (± 8.6%) i/s -      1.072M in   5.062083s
#
# Comparison:
# Incrementing Single Constant Key:               6630475.9 i/s
# Incrementing Many Constant Keys:                4750865.8 i/s - 1.40x  slower
# Incrementing Single Constant Key with a Mutex:  3793805.1 i/s - 1.75x  slower
#
# Incrementing Single Array Key:                   404191.3 i/s - 16.40x  slower
# Incrementing Many Array Keys:                    392789.2 i/s - 16.88x  slower
# Incrementing Single Array Key with a Mutex:      369171.3 i/s - 17.96x  slower
#
# Incrementing Single Hash Key:                    236976.1 i/s - 27.98x  slower
# Incrementing Single Hash Key with a Mutex:       232301.7 i/s - 28.54x  slower
# Incrementing Many Hash Keys:                     213523.0 i/s - 31.05x  slower

