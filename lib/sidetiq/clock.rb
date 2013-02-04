module Sidetiq
  configure do |config|
    config.priority = Thread.main.priority
    config.resolution = 1
    config.lock_expire = 1000
    config.utc = false
  end

  # Public: The Sidetiq clock.
  class Clock
    include Singleton
    include MonitorMixin

    # Public: Start time offset from epoch used for calculating run
    # times in the Sidetiq schedules.
    START_TIME = Sidetiq.config.utc ? Time.utc(2010, 1, 1) : Time.local(2010, 1, 1)

    # Public: Returns a hash of Sidetiq::Schedule instances.
    attr_reader :schedules

    # Public: Returns the clock thread.
    attr_reader :thread

    def self.method_missing(meth, *args, &block)
      instance.__send__(meth, *args, &block)
    end

    def initialize # :nodoc:
      super
      @schedules = {}
    end

    # Public: Get the schedule for `worker`.
    #
    # worker - A Sidekiq::Worker class
    #
    # Examples
    #
    #   schedule_for(MyWorker)
    #   # => Sidetiq::Schedule
    #
    # Returns a Sidetiq::Schedule instances.
    def schedule_for(worker)
      schedules[worker] ||= Sidetiq::Schedule.new(START_TIME)
    end

    # Public: Issue a single clock tick.
    #
    # Examples
    #
    #   tick
    #   # => Hash of Sidetiq::Schedule objects
    #
    # Returns a hash of Sidetiq::Schedule instances.
    def tick
      @tick = gettime
      synchronize do
        schedules.each do |worker, schedule|
          if schedule.schedule_next?(@tick)
            enqueue(worker, schedule.next_occurrence(@tick))
          end
        end
      end
    end

    # Public: Returns the current time used by the clock.
    #
    # Sidetiq::Clock uses `clock_gettime()` on UNIX systems and
    # `mach_absolute_time()` on Mac OS X.
    #
    # Examples
    #
    #   gettime
    #   # => 2013-02-04 12:00:45 +0000
    #
    # Returns a Time instance.
    def gettime
      Sidetiq.config.utc ? clock_gettime.utc : clock_gettime
    end

    # Public: Starts the clock unless it is already running.
    #
    # Examples
    #
    #   start!
    #   # => Thread
    #
    # Returns the Thread instance of the clock thread.
    def start!
      return if ticking?

      Sidekiq.logger.info "Sidetiq::Clock start"
      @thread = Thread.start { clock { tick } }
      @thread.abort_on_exception = true
      @thread.priority = Sidetiq.config.resolution
      @thread
    end

    # Public: Stops the clock if it is running.
    #
    # Examples
    #
    #   stop!
    #   # => nil
    #
    # Returns nil.
    def stop!
      if ticking?
        @thread.kill
        Sidekiq.logger.info "Sidetiq::Clock stop"
      end
    end

    # Public: Returns the status of the clock.
    #
    # Examples
    #
    #   ticking?
    #   # => false
    #
    #   start!
    #   ticking?
    #   # => true
    #
    # Returns true or false.
    def ticking?
      @thread && @thread.alive?
    end

    private

    def enqueue(worker, time)
      key = "sidetiq:#{worker.name}"

      synchronize_clockworks("#{key}:lock") do |redis|
        status = redis.get(key)

        if status.nil? || status.to_f < time.to_f
          time_f = time.to_f
          Sidekiq.logger.info "Sidetiq::Clock enqueue #{worker.name} (at: #{time_f})"
          redis.set(key, time_f)
          worker.perform_at(time)
        end
      end
    end

    def synchronize_clockworks(lock)
      Sidekiq.redis do |redis|
        if redis.setnx(lock, 1)
          Sidekiq.logger.debug "Sidetiq::Clock lock #{lock} #{Thread.current.inspect}"

          redis.pexpire(lock, Sidetiq.config.lock_expire)
          yield redis
          redis.del(lock)

          Sidekiq.logger.debug "Sidetiq::Clock unlock #{lock} #{Thread.current.inspect}"
        end
      end
    end

    def clock
      loop do
        yield
        Thread.pass
        sleep Sidetiq.config.resolution
      end
    end
  end
end

