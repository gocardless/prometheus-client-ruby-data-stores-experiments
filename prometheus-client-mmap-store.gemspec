# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name              = 'prometheus-client-mmap-store'
  s.version           = '0.0.1'
  s.summary           = 'MMap Store (Experimental) for prometheus-client gem'
  s.authors           = ['Daniel Magliola']
  s.email             = ['dmagliola@crystalgears.com']
  s.homepage          = 'https://github.com/gocardless/prometheus-client-ruby-data-stores-experiments'
  s.license           = 'MIT'

  s.files             = ['data_stores/mmap_store.rb']
  s.require_paths     = ['data_stores']

  s.add_dependency 'mmap2'
  s.add_dependency 'concurrent-ruby'
end
