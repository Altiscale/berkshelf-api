module Berkshelf::API
  class CacheBuilder
    module Worker
      class Base
        INTERVAL = 5

        include Celluloid
        include Berkshelf::API::Logging
        include Berkshelf::API::Mixin::Services

        attr_reader :options

        # @option options [Boolean] :eager_build (true)
        #   immediately begin building the cache
        def initialize(options = {})
          @options = { eager_build: true }.merge(options)
          async(:build) if @options[:eager_build]
        end

        # @abstract
        #
        # @param [RemoteCookbook] remote
        #
        # @return [Ridley::Chef::Cookbook::Metadata]
        def metadata(remote)
          raise RuntimeError, "must be implemented"
        end

        # @abstract
        #
        # @return [Array<RemoteCookbook>]
        #  The list of cookbooks this builder can find
        def cookbooks
          raise RuntimeError, "must be implemented"
        end

        def build
          return if @building

          log.info "#{self} building..."

          loop do
            @building = true

            log.info "#{self} determining if the cache is stale..."
            if stale?
              log.info "#{self} cache is stale."
              update_cache
            else
              log.info "#{self} cache is up to date."
            end

            sleep INTERVAL
            clear_diff
          end
        end

        # @return [Array<Array<RemoteCookbook>, Array<RemoteCookbook>>]
        def diff
          @diff ||= cache_manager.diff(cookbooks)
        end

        def update_cache
          created_cookbooks, deleted_cookbooks = diff

          log.info "#{self} adding (#{created_cookbooks.length}) items..."
          created_cookbooks.collect do |remote|
            [ remote, future(:metadata, remote) ]
          end.each do |remote, metadata|
            cache_manager.add(remote.name, remote.version, metadata.value)
          end

          log.info "#{self} removing (#{deleted_cookbooks.length}) items..."
          deleted_cookbooks.each { |remote| cache_manager.remove(remote.name, remote.version) }

          log.info "#{self} cache updated."
          cache_manager.save
        end

        def stale?
          created_cookbooks, deleted_cookbooks = diff
          created_cookbooks.any? || deleted_cookbooks.any?
        end

        private

          def clear_diff
            @diff = nil
          end
      end
    end
  end
end

Dir["#{File.dirname(__FILE__)}/worker/*.rb"].sort.each do |path|
  require_relative "worker/#{File.basename(path, '.rb')}"
end