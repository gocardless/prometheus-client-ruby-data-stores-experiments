# Performance Benchmarks

In the original discussion of the pre-fork server issue, there were some references to
performances, and what can / can't be expected of Ruby.

The goal we're aiming for is for [a counter increment to be sub-microsecond](https://github.com/prometheus/client_ruby/issues/9#issuecomment-254225268)
It's [debatable](https://github.com/prometheus/client_ruby/issues/9#issuecomment-254236891) 
whether this is [even possible in Ruby](https://github.com/prometheus/client_ruby/issues/9#issuecomment-254240330).

Our first approach to this was running a bunch of benchmarks on really basic things to 
see what was realistic to expect. We also ran some other benchmarks to troubleshoot /
make sure the performance numbers we were seeing in our "stores" were actually accurate, 
and we weren't missing something. Finally, we had a "main" benchmark that compares the
performance of different stores. This last one is included in our proposal in the main repo,
but it's duplicated here to include all the extra stores that we are sharing in this repo.


## Running the benchmarks

From the root directory of this repo:

```ruby
bundle exec ruby benchmarks/{{benchmark_file}}.rb
```


## Our testing machine

We ran all of these benchmarks on a Google Cloud Compute instance, with these settings: 

- 4 vCPUs, 4 GB memory
- Intel Skylake
- standard persistent disk (not SSD)
- europe-west4-a
- Ubuntu 18.04 LTS

Please note that a lot of these benchmarks, particularly the ones that involve files, 
will give *radically* different results when run on MacOS. If you're seeing very different
results, make sure you're on Linux.

Also, if you have the Dropbox app in your laptop, at least on MacOS, that'll completely 
destroy all disk access. 


## What each benchmark is trying to achieve

### `hash_raw.rb`

This tries to answer the basic question "How fast is is to set a key in a Hash?", in a 
number of variants that are relevant to our Prometheus Client, namely:

- Simply incrementing a value in a Hash with a single, constant Key (this should be as fast as it gets)
- Incrementing values in a Hash with 1000 constant keys 
- Incrementing values in a Hash whose keys are in turn Hashes (which is how we're representing our metrics)
- Incrementing values with a Mutex around it, to gauge what kind of overhead Mutexes add.

**Verdict:**
- Using constant keys, just a Hash with a Mutex around it should allow us to be sub-microsecond.
- **HOWEVER**, if we use Hashes as the keys to these arrays, then we're well over a microsecond
  (around 4µs with a Mutex)
- If we use Arrays as keys, instead of Hashes (similar to what the Python Client does),
  it's faster than Hashes, but we're still around 2.7µs.
- Finally, as we learn from the `hash_keys_marshall` benchmark, flattening the Hash keys
  to a string would also be slower than 1µs. 


### `hash_keys_marshall.rb`

Some of our stores (`DirectFileStore`, `Mmap`, `Redis`) can't use Hashes as their keys,
and need to dump those into a String. 

The most natural Ruby way to do this is `to_json`, but it turns out, that can also be the
bottleneck in our stores, since it's actually pretty slow.

This benchmark attempts a bunch of different things to see what is faster.

NOTE: While the absolute fastest was to either map into a querystring without escaping 
components, or to join arrays using an "unusual separator", both of these are somewhat
unsafe. It's likely that this won't be an actual problem with realistic labelsets, but
we opted for the safer `CGI::escape` variant of making a querystring, since the slowdown
was small enough to prefer safety. 

Interestingly, this finding doesn't apply to JRuby at all, where `to_json` is about 
twice as fast as our choice of option. This is fine, since JRuby users will probably
not use any of the multi-process solutions that rely on this kind of serializing.

### `flock.rb`

Some stores (`PStore`, `DirectFileStore`) rely on having multiple files for a metric,
and reading all of them on a scrape. These rely on `flock` to keep reads consistent.
We all know "syscalls are slow", this checks how slow this particular one is...

Result: About 0.75µs


### `redis_raw.rb`

In our tests of the `Redis` data store, we were getting results that went completely
against our intuitions. Particularly on multiple-threads. The main assumption was that
Redis calls fell squarely under "I/O", and we should be going faster on multiple threads
than on a single one, while the benchmarks showed the same exact "total" time, independent
of thread count. One initial hypothesis was that maybe we had a lock somewhere that we didn't realize.

This super-basic benchmark tries to get realistic numbers for the single-threaded scenario,
to make sure we weren't missing something.

Verdict: We weren't, Redis was really much slower than we expected. About 60µs per 
roundtrip. Sad times.


### `threads.rb`

As mentioned above, we weren't seeing the kinds of speedups we were expecting when adding
threads to what seemed like highly I/O bound operations.

This benchmark tests PStore and Redis (with and without a connection pool) to see how
they react in multi-threaded scenarios, to make sure what we were seeing wasn't because
of a lock somewhere else in the code.

Verdict: 
- Apparently, neither calling Redis, nor writing to a PStore (without `fsyncing`) 
  are "I/O bound enough" for us to gain anything using threads.
- In fact, with PStores, we get significant slowdowns with multiple threads, even though 
  there shouldn't be contention (each thread uses its own file) 
- It's quite interesting to see the difference here between MRI and JRuby, where the 
  threads do actually significantly reduce runtime.
- It's also quite interesting how much overhead the Redis connection pool adds (about 50%)


### `data_stores.rb`

This is the same benchmark that is in the main repo, comparing all data stores, with the
difference that this one includes all the "extra" stores from this repo.


#### HDD vs SSD vs TMPFS

For the stores that write to disk, we're running twice, once on an HDD (not SSD), and once
on a TMPFS directory. When originally developing, we also ran on SSD. All three of these
give more or less the same results, mostly because we're not `fsync`ing the files, so the
disks don't really get hit.

In order to run these tests yourself, you'll need to create a directory, mount it as `tmpfs`, 
and modify the constant `TMPFS_DIR`

#### "Realistic" vs "Simple" scenarios

This test was originally written to simulate a "reasonably realistic" scenario. This means
a mixture of counters and histograms (heavily biased towards counters), and a mixture of
label counts. This scenario should give a reasonably realistic expectation of how long
each increment would take on a general app

Because both labels and histograms add overhead to the stores, however, this is not great
for testing the stores themselves. For this, it's better to use a scenario with just counters
and no labels, which gives us "purer" numbers, and it's the number we actually want, when
comparing against the "sub-microsecond counter increment" goal stated at the top. 

Because of this, the "simple" scenario is the default. Look for the commented out constants
`NUM_COUNTERS`, `NUM_HISTOGRAMS`, `MIN_LABELS` and `MAX_LABELS` to switch between these
two scenarios
