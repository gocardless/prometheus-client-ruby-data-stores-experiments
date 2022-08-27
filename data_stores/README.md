# Redis data store for prometheus-client

This project is a fork of [gocardless/prometheus-client-ruby-data-stores-experiments] (https://github.com/gocardless/prometheus-client-ruby-data-stores-experiments)

The original project had other kinds of data stores that has their own dependencies which was quite limiting to move with Ruby 3. So we are taking the approach of separating the Redis datastore, which can be run in Ruby 3.

## Thanks to [GoCardless](https://github.com/gocardless)

Thanks to GoCardless for the original experimentation on the various kinds of data stores for prometheus-client. This is simply a copy of their original project and removed all other data stores. This will be easier to manage the redis-store without all other dependencies.

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
