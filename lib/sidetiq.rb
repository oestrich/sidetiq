# stdlib
require 'monitor'
require 'ostruct'
require 'singleton'

# gems
require 'ice_cube'
require 'sidekiq'

# c extensions
require 'sidetiq_ext'

# internal
require 'sidetiq/config'
require 'sidetiq/clock'
require 'sidetiq/middleware'
require 'sidetiq/schedule'
require 'sidetiq/schedulable'
require 'sidetiq/version'

# The Sidetiq namespace.
module Sidetiq
  class << self
    # Public: Returns an Array of workers including Sidetiq::Schedulable.
    def workers
      schedules.keys
    end

    # Public: Returns a Hash of Sidetiq::Schedule instances.
    def schedules
      Clock.synchronize do
        Clock.schedules.dup
      end
    end

    # Public: Currently scheduled recurring jobs.
    #
    # worker - A Sidekiq::Worker class or String of the class name (optional)
    # block  - An optional block that can be given to which each
    #          Sidekiq::SortedEntry instance corresponding to a scheduled job will
    #          be yielded.
    #
    # Examples
    #
    #   Sidetiq.scheduled
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.scheduled(MyWorker)
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.scheduled("MyWorker")
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.scheduled do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.scheduled(MyWorker) do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.scheduled("MyWorker") do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    # Yields each Sidekiq::SortedEntry instance.
    # Returns an Array of Sidekiq::SortedEntry objects.
    def scheduled(worker = nil, &block)
      filter_set(Sidekiq::ScheduledSet.new, worker, &block)
    end

    # Public: Recurring jobs currently scheduled for retries.
    #
    # worker - A Sidekiq::Worker class or String of the class name (optional)
    # block  - An optional block that can be given to which each
    #          Sidekiq::SortedEntry instance corresponding to a scheduled job will
    #          be yielded.
    #
    # Examples
    #
    #   Sidetiq.retries
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.retries(MyWorker)
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.retries("MyWorker")
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.retries do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.retries(MyWorker) do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    #   Sidetiq.retries("MyWorker") do |job|
    #     # do stuff ...
    #   end
    #   # => [#<Sidekiq::SortedEntry>, ...]
    #
    # Yields each Sidekiq::SortedEntry instance.
    # Returns an Array of Sidekiq::SortedEntry objects.
    def retries(worker = nil, &block)
      filter_set(Sidekiq::RetrySet.new, worker, &block)
    end

    private

    def filter_set(set, worker, &block)
      worker = worker.constantize if worker.kind_of?(String)

      jobs = set.select do |job|
        klass = job.klass.constantize
        ret = klass.include?(Schedulable)
        ret = ret && klass == worker if worker
        ret
      end

      jobs.each(&block) if block_given?

      jobs
    end
  end
end
