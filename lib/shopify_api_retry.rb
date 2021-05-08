# frozen_string_literal: true

require "shopify_api"

module ShopifyAPIRetry
  VERSION = "0.1.3"

  class Config                  # :nodoc:
    attr_writer :default_wait
    attr_writer :default_tries

    def initialize
      @settings = {}
    end

    def default_wait
      @default_wait ||= nil
    end

    def default_tries
      @default_tries ||= 2
    end

    def on(errors, options = nil)
      options = (options || {}).dup
      options[:wait] ||= default_wait
      options[:tries] ||= default_tries

      Array(errors).each do |status_or_class|
        @settings[status_or_class] = options
      end
    end

    def clear
      @settings.clear
      @default_wait = nil
      @default_tries = nil
    end

    def merge(userconfig)
      config = to_h
      return config unless userconfig

      if userconfig.is_a?(Integer)
        warn "#{self.class}: using an Integer for the retry time is deprecated and will be removed, use :wait => #{userconfig} instead"
        userconfig = { :wait => userconfig }
      elsif !userconfig.is_a?(Hash)
        raise ArgumentError, "config must be a Hash"
      end

      userconfig.each do |k, v|
        if v.is_a?(Hash)
          config[k.to_s] = v.dup
        else
          config["graphql"][k] = config[REST::HTTP_RETRY_STATUS][k] = v
        end
      end

      config.values.each do |cfg|
        raise ArgumentError, "seconds to wait must be >= 0" if cfg[:wait] && cfg[:wait] < 0
      end

      config
    end

    def to_h
      settings = {
        "graphql" => { :tries => default_tries, :wait => default_wait },
        REST::HTTP_RETRY_STATUS => { :tries => default_tries, :wait => default_wait }
      }

      @settings.each_with_object(settings) { |(k, v), o| o[k.to_s] = v.dup }
    end
  end

  @config = Config.new

  def self.configure
    return @config unless block_given?
    yield @config
    nil
  end

  def self.config
    @config
  end

  class Request                 # :nodoc:
    def self.retry(cfg = nil, &block)
      new(cfg).retry(&block)
    end

    def initialize(cfg = nil)
      @handlers = ShopifyAPIRetry.config.merge(cfg)
    end

    def retry(&block)
      raise ArgumentError, "block required" unless block_given?

      begin
        result = request(&block)
      rescue => e
        handler = find_handler(e)
        raise unless handler && snooze(handler)

        retry
      end

      result
    end

    protected

    attr_reader :handlers

    def request
      yield
    end

    def find_handler(error)
      @handlers[error.class.name]
    end

    def snooze(handler)
      handler[:attempts] ||= 1
      return false if handler[:attempts] == handler[:tries]

      snooze = handler[:wait].to_f
      waited = sleep snooze
      snooze = snooze - waited
      # sleep returns the rounded time slept but sometimes it's rounded up, others it's down
      # given this, we may sleep for more than requested
      sleep snooze if snooze > 0

      handler[:attempts] += 1

      true
    end
  end

  class REST < Request
    HTTP_RETRY_AFTER = "Retry-After"
    HTTP_RETRY_STATUS = "429"

    protected

    def find_handler(error)
      handler = super
      return handler if handler || (!error.is_a?(ActiveResource::ConnectionError) || !error.response.respond_to?(:code))

      handler = handlers[error.response.code] || handlers["#{error.response.code[0]}XX"]
      handler[:wait] ||= error.response[HTTP_RETRY_AFTER] || config.default_wait if error.response.code == HTTP_RETRY_STATUS

      handler
    end
  end

  class GraphQL < Request
    CONVERSION_WARNING = "#{name}.retry: skipping retry, cannot convert GraphQL response to a Hash: %s. " \
                         "To retry requests your block's return value must be a Hash or something that can be converted via #to_h"
    protected

    def request
      loop do
        data = og_data = yield

        # Shopify's client does not return a Hash but
        # technically we work with any Hash response
        unless data.is_a?(Hash)
          unless data.respond_to?(:to_h)
            warn CONVERSION_WARNING % "respond_to?(:to_h) is false"
            return og_data
          end

          begin
            data = data.to_h
          rescue TypeError, ArgumentError => e
            warn CONVERSION_WARNING % e.message
            return og_data
          end
        end

        cost = data.dig("extensions", "cost")
        # If this is nil then the X-GraphQL-Cost-Include-Fields header was not set
        # If actualQueryCost is present then the query was not rate limited
        return og_data if cost.nil? || cost["actualQueryCost"]

        handler = handlers["graphql"]
        handler[:wait] ||= sleep_time(cost)

        return og_data unless snooze(handler)
      end
    end

    def sleep_time(cost)
      status = cost["throttleStatus"]
      (cost["requestedQueryCost"] - status["currentlyAvailable"]) / status["restoreRate"]# + 0.33
    end
  end

  def retry(cfg = nil, &block)
    warn "#{name}.retry has been deprecated, use ShopifyAPIRetry::REST.retry or ShopifyAPIRetry::GraphQL.retry"
    REST.new(cfg).retry(&block)
  end

  module_function :retry
end
