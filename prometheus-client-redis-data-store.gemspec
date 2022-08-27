# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name              = 'prometheus-client-redis-data--store'
  s.version           = '0.0.1'
  s.summary           = 'Redis Store for prometheus-client gem'
  s.authors           = ['Daniel Magliola', 'Balaji Raghavan']
  s.email             = ['dmagliola@crystalgears.com', 'bala@molecule.io']
  s.homepage          = 'https://github.com/wearemolecule/prometheus-client-redis-data-store'
  s.license           = 'MIT'

  s.files             = ['data_stores/redis_store.rb']
  s.require_paths     = ['data_stores']

  s.add_dependency 'concurrent-ruby'
end
