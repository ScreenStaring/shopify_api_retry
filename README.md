# Shopify API Retry

![CI](https://github.com/ScreenStaring/shopify_api_retry/workflows/CI/badge.svg)

Simple Ruby module to retry a [Shopify API request](https://github.com/Shopify/shopify_api) if rate limited (HTTP 429) or other errors
occur.

## Installation

Bundler:

```rb
gem "shopify_api_retry"
```

Gem:

```
gem install shopify_api_retry
```

## Usage

By default requests are retried when a Shopify rate limit error is returned. The retry happens once after waiting for
[the seconds given by the HTTP `Retry-After` header](https://shopify.dev/concepts/about-apis/rate-limits):
```rb
require "shopify_api_retry" # requires "shopify_api" for you

ShopifyAPIRetry.retry { customer.update_attribute(:tags, "foo") }
customer = ShopifyAPIRetry.retry { ShopifyAPI::Customer.find(id) }
```

You can override this:
```rb
ShopifyAPIRetry.retry(:wait => 3, :tries => 5) { customer.update_attribute(:tags, "foo")  }
```
This will try the request 5 times, waiting 3 seconds between each attempt. If a retry fails after the given number
of `:tries` the original error will be raised.

You can also retry requests when other errors occur:
```rb
ShopifyAPIRetry.retry "5XX" => { :wait => 10, :tries => 2 } do
  customer.update_attribute(:tags, "foo")
end
```
This still retries rate limit requests, but also all HTTP 5XX errors.

Classes can be specified too:
```rb
ShopifyAPIRetry.retry SocketError => { :wait => 1, :tries => 5 } do
  customer.update_attribute(:tags, "foo")
end
```

Global defaults can be set as well:
```rb
ShopifyAPIRetry.configure do |config|
  config.default_wait  = 2.5
  config.default_tries = 10

  # Use defaults for these
  config.on ["5XX", Net::TimeoutError]

  config.on SocketError, :tries => 2, :wait => 1
end

ShopifyAPIRetry.retry { customer.update_attribute(:tags, "foo")  }
```

## License

Released under the MIT License: www.opensource.org/licenses/MIT

---

Made by [ScreenStaring](http://screenstaring.com)
