require 'redis'

module Dockistrano

  class Hipache

    def initialize(hipache_url)
      @hipache_url = hipache_url
    end

    def online?
      redis.ping
    rescue Redis::CannotConnectError
      false
    end

    def wait_for_online
      tries = 0
      while !online? and tries < 5
        Kernel.sleep 1
        tries += 1
      end
    end

    def register(container, hostname, ip_address, port)
      wait_for_online

      raise "Cannot connect to Redis server, registration failed" unless online?

      unless redis.lrange("frontend:#{hostname}", 0, -1).empty?
        redis.del("frontend:#{hostname}")
      end

      redis.rpush("frontend:#{hostname}",  container)
      redis.rpush("frontend:#{hostname}",  "http://#{ip_address}:#{port}")
    end

    def unregister(container, hostname, ip_address, port)
      if online?
        redis.lrem("frontend:#{hostname}", 0, "http://#{ip_address}:#{port}")
      end
    end

    def status
      mappings = {}
      if online?
        redis.keys("frontend:*").each do |key|
          host = key.gsub(/^frontend:/, "")
          mappings[host] = redis.lrange(key, 1, -1)
        end
      end
      mappings
    end

    private

    def redis
      @redis ||= Redis.new(url: @hipache_url)
    end

  end
end
