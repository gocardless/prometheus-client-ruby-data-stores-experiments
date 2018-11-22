# Prometheus Ruby Client Data Stores Experiments

As part of our proposal of having [Swappable Data Stores](https://github.com/prometheus/client_ruby/pull/95)
for the Ruby Client, we wrote many different stores, and ran a significant number of 
benchmarks to make sure our proposal performed adequately, and to choose what was the
sweet spot of runtime performance, code simplicity, and confidence / stability of each
store, to decide which stores should be proposed as the official ones.

In the repository, we share *all* the different stores that we wrote, plus all the 
benchmark and test scripts we created to make sure things worked the way we expected,
and the results of those benchmarks.



## Running Tests

The Data Stores included in this repo have tests. Simply run:

```ruby
bundle exec rspec
```

**WARNING:** The Specs for the Redis store start by flushing DB #13. If you have data
in Redis, in DBs other than 0 (the default), you might want to check #13 before running
these tests, or your data may go away.
