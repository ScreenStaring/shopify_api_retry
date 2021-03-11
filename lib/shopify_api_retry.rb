# frozen_string_literal: true

require "shopify_api"

module ShopifyAPIRetry
  VERSION = "0.1.1"

  HTTP_RETRY_AFTER = "Retry-After"
  HTTP_RETRY_STATUS = "429"

  class Config
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

    def to_h
      settings = { HTTP_RETRY_STATUS => { :tries => default_tries, :wait => default_wait } }
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

  #
  # Execute the provided block. If an HTTP 429 response is returned try
  # it again. If any errors are provided try them according to their wait/return spec.
  #
  # If no spec is provided the value of the HTTP header <code>Retry-After</code>
  # is waited for before retrying. If it's not given (it always is) +2+ is used.
  #
  # If retry fails the original error is raised.
  #
  # Returns the value of the block.
  #
  def retry(cfg = nil)
    raise ArgumentError, "block required" unless block_given?

    attempts = build_config(cfg)

    begin
      result = yield
    rescue => e
      handler = attempts[e.class.name]
      raise if handler.nil? && (!e.is_a?(ActiveResource::ConnectionError) || !e.response.respond_to?(:code))

      handler ||= attempts[e.response.code] || attempts["#{e.response.code[0]}XX"]
      handler[:wait] ||= e.response[HTTP_RETRY_AFTER] || config.default_wait if e.response.code == HTTP_RETRY_STATUS

      handler[:attempts] ||= 1
      raise if handler[:attempts] == handler[:tries]

      snooze = handler[:wait].to_i
      waited = sleep snooze
      snooze -= waited
      # Worth looping?
      sleep snooze if snooze > 0

      handler[:attempts] += 1

      retry
    end

    result
  end

  module_function :retry

  def self.build_config(userconfig)
    config = ShopifyAPIRetry.config.to_h
    return config unless userconfig

    if userconfig.is_a?(Integer)
      userconfig = { :wait => config }
      warn "passing an Integer to retry is deprecated and will be removed, use :wait => #{config} instead"
    elsif !userconfig.is_a?(Hash)
      raise ArgumentError, "config must be a Hash"
    end

    userconfig.each do |k, v|
      if v.is_a?(Hash)
        config[k.to_s] = v.dup
      else
        config[HTTP_RETRY_STATUS][k] = v
      end
    end

    config.values.each do |cfg|
      raise ArgumentError, "seconds to wait must be >= 0" if cfg[:wait] && cfg[:wait] < 0
    end

    config
  end

  private_class_method :build_config
end
