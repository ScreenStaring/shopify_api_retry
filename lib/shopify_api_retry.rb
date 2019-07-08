require "shopify_api"

module ShopifyAPIRetry
  VERSION = "0.0.1".freeze
  HTTP_RETRY_AFTER = "Retry-After".freeze

  #
  # Execute the provided block. If an HTTP 429 response is return try
  # it again.  If no retry time is provided the value of the HTTP header <code>Retry-After</code>
  # is used. If it's not given (it always is) +2+ is used.
  #
  # If retry fails the original error is raised (`ActiveResource::ClientError` or subclass).
  #
  # Returns the value of the block.
  #
  def retry(seconds_to_wait = nil)
    raise ArgumentError, "block required" unless block_given?
    raise ArgumentError, "seconds to wait must be > 0" unless seconds_to_wait.nil? || seconds_to_wait > 0

    result = nil
    retried = false

    begin
      result = yield
    rescue ActiveResource::ClientError => e
      # Not 100% if we need to check for code method, I think I saw a NoMethodError...
      raise unless !retried && e.response.respond_to?(:code) && e.response.code.to_i == 429

      seconds_to_wait = (e.response[HTTP_RETRY_AFTER] || 2).to_i unless seconds_to_wait
      sleep seconds_to_wait

      retried = true
      retry
    end

    result
  end

  module_function :retry
end
