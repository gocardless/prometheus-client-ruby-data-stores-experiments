# Prometheus Ruby Client Data Stores Experiments

As part of our proposal of having [Swappable Data Stores](https://github.com/prometheus/client_ruby/pull/95)
for the Ruby Client, we wrote many different stores, and ran a significant number of 
benchmarks to make sure our proposal performed adequately, and to choose what was the
sweet spot of runtime performance, code simplicity, and confidence / stability of each
store, to decide which stores should be proposed as the official ones.

In the repository, we share *all* the different stores that we wrote, plus all the 
benchmark and test scripts we created to make sure things worked the way we expected,
and the results of those benchmarks.


## Repo Contents

- **Benchmarks**: All our basic and detailed benchmarks, in the `/benchmarks` directory.
- **Data Stores**: All the other data stores we created in the process of proposing the
    3 that ended up in the official repo. In the `/data_stores` directory.
- **Tests for the data stores**: In the `/spec` directory.

## Running Tests

The Data Stores included in this repo have tests. Simply run:

```ruby
bundle exec rspec
```

**WARNING:** The Specs for the Redis store start by flushing DB #13. If you have data
in Redis, in DBs other than 0 (the default), you might want to check #13 before running
these tests, or your data may go away.
