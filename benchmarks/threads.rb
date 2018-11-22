require 'pstore'
require 'connection_pool'
require 'redis'

DATA_POINTS = 100_000
VERBOSE = false

def pstore(num_threads)
  print "PStore ".ljust(25)
  print "x #{ num_threads }".ljust(5)

  globalstart = Time.now.to_f

  threads = (1..num_threads).map do |i|
    Thread.new do
      begin
        start = Time.now.to_f
        counter = 0
        puts "Thread #{ i }: #{ start }" if VERBOSE

        ps = PStore.new("store#{i}.pstore")
        (DATA_POINTS / num_threads).times do
          ps.transaction do
            ps[:aa] = ps.fetch(:aa, 0) + 1
          end
          counter += 1
        end

        endt = Time.now.to_f
        puts "Done #{ i }: #{ endt } (#{ endt - start }s) - Iter: #{ counter }" if VERBOSE
      rescue StandardError => e
        puts e.inspect
      end
    end
  end

  threads.each { |t| t.join }
  globalendt = Time.now.to_f
  puts "Done: #{ globalendt - globalstart }s"
end

def redis_no_pool(num_threads)
  print "Redis no pool ".ljust(25)
  print "x #{ num_threads }".ljust(5)

  globalstart = Time.now.to_f

  threads = (1..num_threads).map do |i|
    Thread.new do
      begin
        conn = Redis.new
        start = Time.now.to_f
        counter = 0
        puts "Thread #{ i }: #{ start }" if VERBOSE

        (DATA_POINTS / num_threads).times do
          conn.incr(:aa)
          counter += 1
        end

        endt = Time.now.to_f
        puts "Done #{ i }: #{ endt } (# {endt - start }s) - Iter: #{ counter }" if VERBOSE
      rescue StandardError => e
        puts e.inspect
      end
    end
  end

  threads.each { |t| t.join }
  globalendt = Time.now.to_f
  puts "Done: #{ globalendt - globalstart }s"
end

def redis_with_pool(num_threads)
  print "Redis with pool ".ljust(25)
  print "x #{ num_threads }".ljust(5)

  conn_pool = ConnectionPool.new(size: 30) { Redis.new }

  globalstart = Time.now.to_f
  threads = (1..num_threads).map do |i|
    Thread.new do
      begin
        start = Time.now.to_f
        counter = 0
        puts "Thread #{ i }: #{ start }" if VERBOSE

        (DATA_POINTS / num_threads).times do
          conn_pool.with do |conn|
            conn.incr(:aa)
          end
          counter += 1
        end

        endt= Time.now.to_f
        puts "Done #{ i }: #{ endt } (#{ endt - start }s) - Iter: #{ counter }" if VERBOSE
      rescue StandardError => e
        puts e.inspect
      end
    end
  end

  threads.each { |t| t.join }
  globalendt = Time.now.to_f
  puts "Done: #{ globalendt - globalstart }s"
end

[:redis_no_pool, :redis_with_pool, :pstore].each do |method|
  [1,2,3,4,6,8,10,12,16,20].each do |num_threads|
    send(method, num_threads)
  end
  3.times { puts "" }
end

# Results: (MRI)
#
# Redis no pool            x 1  Done: 6.062342882156372s
# Redis no pool            x 2  Done: 6.096405982971191s
# Redis no pool            x 3  Done: 6.0605309009552s
# Redis no pool            x 4  Done: 6.292366027832031s
# Redis no pool            x 6  Done: 6.974467039108276s
# Redis no pool            x 8  Done: 7.370119333267212s
# Redis no pool            x 10 Done: 7.864893198013306s
# Redis no pool            x 12 Done: 8.429535865783691s
# Redis no pool            x 16 Done: 8.397820949554443s
# Redis no pool            x 20 Done: 7.5002710819244385s
#
# Redis with pool          x 1  Done: 9.736681938171387s
# Redis with pool          x 2  Done: 8.831906080245972s
# Redis with pool          x 3  Done: 8.933444023132324s
# Redis with pool          x 4  Done: 9.113560676574707s
# Redis with pool          x 6  Done: 10.43388295173645s
# Redis with pool          x 8  Done: 9.583637952804565s
# Redis with pool          x 10 Done: 7.126535892486572s
# Redis with pool          x 12 Done: 7.201736927032471s
# Redis with pool          x 16 Done: 7.01915717124939s
# Redis with pool          x 20 Done: 7.698308229446411s
#
# PStore                   x 1  Done: 2.87221097946167s
# PStore                   x 2  Done: 7.328192710876465s
# PStore                   x 3  Done: 9.474627494812012s
# PStore                   x 4  Done: 11.188106298446655s
# PStore                   x 6  Done: 11.816618919372559s
# PStore                   x 8  Done: 11.618850469589233s
# PStore                   x 10 Done: 11.580385446548462s
# PStore                   x 12 Done: 11.514492750167847s
# PStore                   x 16 Done: 11.748090267181396s
# PStore                   x 20 Done: 11.553555011749268s
#
# --------------------------------
#
# Results: (JRuby)
#
# Redis no pool            x 1  Done: 6.3268883228302s
# Redis no pool            x 2  Done: 4.1656248569488525s
# Redis no pool            x 3  Done: 3.2826790809631348s
# Redis no pool            x 4  Done: 2.699002981185913s
# Redis no pool            x 6  Done: 2.603957176208496s
# Redis no pool            x 8  Done: 2.6231768131256104s
# Redis no pool            x 10 Done: 2.5901858806610107s
# Redis no pool            x 12 Done: 2.559507131576538s
# Redis no pool            x 16 Done: 2.7885570526123047s
# Redis no pool            x 20 Done: 2.6900837421417236s
#
# Redis with pool          x 1  Done: 9.507444858551025s
# Redis with pool          x 2  Done: 5.0077431201934814s
# Redis with pool          x 3  Done: 3.632086992263794s
# Redis with pool          x 4  Done: 3.8066413402557373s
# Redis with pool          x 6  Done: 3.732480764389038s
# Redis with pool          x 8  Done: 3.5089337825775146s
# Redis with pool          x 10 Done: 3.454943895339966s
# Redis with pool          x 12 Done: 3.5337510108947754s
# Redis with pool          x 16 Done: 3.6643240451812744s
# Redis with pool          x 20 Done: 3.7452552318573s
#
# PStore                   x 1  Done: 4.255526065826416s
# PStore                   x 2  Done: 3.009287118911743s
# PStore                   x 3  Done: 2.5206589698791504s
# PStore                   x 4  Done: 2.4181249141693115s
# PStore                   x 6  Done: 2.3381612300872803s
# PStore                   x 8  Done: 2.4446229934692383s
# PStore                   x 10 Done: 2.3275129795074463s
# PStore                   x 12 Done: 2.3828389644622803s
# PStore                   x 16 Done: 2.6144721508026123s
# PStore                   x 20 Done: 2.3281679153442383s
