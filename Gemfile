source 'https://rubygems.org'

gem 'prometheus-client', :git => 'https://github.com/gocardless/prometheus_client_ruby.git', :branch => 'pluggable_data_stores'
gem 'rspec'

if !defined?(RUBY_ENGINE) || RUBY_ENGINE == "ruby" # MmapStore only works on MRI
  gem 'mmap2'
end

gem 'benchmark-ips'
gem 'connection_pool'
gem 'redis'
gem 'rack'
