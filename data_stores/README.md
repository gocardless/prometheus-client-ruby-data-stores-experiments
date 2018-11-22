# Alternative Data Stores

In the process of extracting Data Storage into pluggable stores, and figuring out what
were the best stores to propose, we ended up creating many different stores, since we
were trying to not make performance assumptions, and measure as much as we could (and 
indeed, a lot of the results defied our expectations).

The 3 stores offering what we considered the best sweet spots made the cut into the main repo,
but we offer here all the other stores, in case they are useful to anyone.

Specifically, some of the performance characteristics we observed may not be the same
for everyone, and in some environments, some of these may be faster than the ones offered
in the main repo.


## MmapStore

The main motivation behind publishing this store is that the Prometheus community seems
to have gravitated towards MMaps for solving the multi-process problem.

We haven't proposed this store for inclusion in the main repo, however, because we don't
consider it stable. In the process of developing it, we've encountered multiple ways in
which it segfaulted. Some of these were reproducible locally, some weren't. Some happened
quite frequently in Travis...

This version of the store seems to work, and we haven't managed to make it segfault. 
However, this doesn't feel like a guarantee, and we are in no way confident in the stability 
of this code, so we don't recommend running it in production without some serious 
checking first. 

That said, it *is* a bit faster than the `DirectFileStore` that we recommend for multi-process
environments, and in your particular runtime situation is may be advantageous to use it.
Just make sure it's not going to segfault on you first.
 
### What it does

This store is quite similar to the `DirectFileStore`. The main difference is that, after
opening the file where data will be stored, it MMaps over it (using the `mmap2` gem, which
provides a significant amount of magic), so it can read/write the file by treating it
like an in-memory byte array.

The store (just like `DirectFileStore`) keeps one Mmapped file per process, and per metric.
When a Prometheus scrape is received in one of the processes, it finds all the
files for a metric, mmaps into them, reads their values and aggregates them.

### `mmap2` seems to not work at all in Ruby 2.1

The `mmap2` gem seems to have a bug (or *something* has a bug) through which, under the 
most basic of circumstances, a Garbage Collection run will segfault.

[This is a reported issue](https://github.com/tenderlove/mmap/issues/5) that we've verified
indeed happens.

Before using this gem, run this code in the environment you'll be running your production
code in, and make sure it doesn't blow up:

```ruby
require 'tempfile'
require 'mmap'

t = Tempfile.new("mmap")
File.open(t,"w"){|f| f.print("abcd")}
m = Mmap.new(t)

m[0..1]
GC.start
```

### More on the segfaults we encountered

This is a dump of all we know about these segfaults, for anyone that would like to try
and "fix" them, or confirm they're no longer there.

The Mmap Store starts with a 1Mb file, and starts writing into it,  moving forward into
the file as it finds new keys (labelsets). If at some point it reaches 1Mb, it "grows" the 
file.

This store, in [its original version](https://github.com/prometheus/client_ruby/blob/multiprocess/lib/prometheus/client/valuetype.rb#L113),
would segfault after [resizing the file](https://github.com/prometheus/client_ruby/blob/multiprocess/lib/prometheus/client/valuetype.rb#L180).
Not immediately after, it seems it did it on the next Garbage Collection. Disabling GC
makes it not segfault anymore, which seems to confirm it's GC. Also, it did this *very*
consistently in our local dev machine.

Changing the resizing code so that it'd `msync`, `munmap`, `flush`, close the file, 
reopen the file, resize it and `mmap` it again fixed the segfault, locally. It would
still segfault in Travis. Again, only when resizing the file. We could not reproduce this
locally.

Changing this to its current incarnation, where it grows the file by calling `mmap.extend`
seems to make it not segfault anymore. Again, we don't know whether this is an actual fix.
We definitely don't trust this code enough to run it in production. 


## Pstore

`Pstore` was our first iteration of a file-based store, to see how fast or slow it was to
just use disk. It's based, as its name implies, on Ruby's `PStore` data structure, which
is a file-based hash. It is, by far, the easiest way of dumping a Hash into disk.

From an internal perspective, it simply uses PStores like a Hash. It has one store per
metric, per process and per *thread*, to try and avoid contention as much as possible.
PStores are multi-process safe, since they have a locking mechanism (based on `flock`)
around every read or write, so they're safe to use for our purposes, but contention can
get quite expensive. The "process safety" then only comes into play when getting scraped
by Prometheus, where we read all the files from all the processes to aggregate values.

Internally, the way `PStore`s work is to simply `Marshal.dump` the internal hash into their
backing file. This is super simple and versatile, but for our purposes it's extremely slow.
Using an approach where we write to specific offsets into the file (like `DirectFileStore` does)
is extremely faster than `Marshal.dump`ing the entire hash for each counter increment.


## Redis

This is a store that keeps all its data in Redis.

The basic idea behind using Redis is that what we need to solve the multi-process problem 
is a shared area in memory that we can access in a controlled, safe, concurrent manner, 
and that's precisely what Redis is.

This store ended up being (on Linux) much slower than accessing disks directly (even with
`PStore`). However, in other environments, it may actually be faster, so if the file-based
stores are too slow for your use case, try running the benchmarks in this repo in your
environment, maybe Redis will help.

It's important to note that for this to work well, each server would need their own local 
Redis server (unlike the usual configuration where there's a shared Redis server for all 
the App servers). Not only we don't want to share data between servers, this store can
only be performant if Redis is accessed through `localhost`. If we're involving an actual 
network, performance will tank to a probably unusable level.

There are a few more caveats. We recommend you read the extensive notes at the top of the 
`Redis` class before running this in production.

### Warning when running tests or benchmarks!

The Redis tests start by flushing the Redis DB they are connecting to. That may involve 
data you had in your Redis instance and were planning to keep. To minimize destruction of 
people's dev machine, both the tests and the benchmark connect to database "13", making it
less likely that there'll be data there. But if you have data on that database, you might
want to change the tests before running them. 


## ConcurrentRubyHash (broken! do not use!)

This was a quick experiment using the [Hash provided by the `concurrent-ruby` gem](http://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/Hash.html), 
which is thread safe. That said, it doesn't work. No matter how thread safe that Hash is,
doing `hash[labels] += 1` is *not* thread safe, even in MRI.

We don't know why, to be honest. The GIL should end up doing this atomically, since we're
not doing any of the (not really documented) things that can make it unlock (like method calls).
Also, with a simple test benchmark that hammers this store in multiple threads, it was
reporting the right numbers, so it *seems* to work. However, when running our performance
benchmark, it reports discrepancies in the result numbers, which look like the typical
race condition when multiple threads increment the same number.

We're leaving this here as a warning not to do this. Even in MRI, if you have a hash,
you need Mutexes around your increments! (Like the `Synchronized` store that comes built-in) 

### About the internals of the `concurrent-ruby Hash`

In MRI, this "safe" hash is basically just the regular Ruby Hash(https://github.com/ruby-concurrency/concurrent-ruby/blob/master/lib/concurrent/hash.rb#L20), 
and it counts exclusively on the GIL for thread safety. This is fine in Ruby
up to 2.5, but that may change in the future, which may require an update to the 
`concurrent-ruby` gem. 


## CentralHashExample

This was just a proof of concept of the Store interface, showing how one could deal with
a single, centralized store for all the data. It does so by merging special values into
the labelsets passed in, and storing everything into a single, Central Hash. 

All this label merging makes it very slow, and there's no reason to do this if we're
using `Hash` as its backing. Still, left here as an example in case it's useful for 
developing other stores
