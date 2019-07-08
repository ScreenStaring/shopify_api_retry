# ShopifyAPIRetry

Simple module to retry a [ShopifyAPI](https://github.com/Shopify/shopify_api) request if an HTTP 429 (too many requests) is returned. No monkey patching.

## Usage

```rb
ShopifyAPIRetry.retry { customer.update_attribute(:tags, "foo")  }
ShopifyAPIRetry.retry(30) { customer.update_attribute(:tags, "foo") }  # Retry after 30 seconds on HTTP 429
customer = ShopifyAPIRetry.retry { ShopifyAPI::Customer.find(id) }
```

If no retry time is provided the value of the HTTP header `Retry-After` is used. If it's not given (it always is) `2` is used.

If the retry fails the original error is raised (`ActiveResource::ClientError` or subclass).

## Installation

Bundler:

```rb
gem "shopify_api_retry"
```

Gem:

```
gem install shopify_api_retry
```

## License

Released under the MIT License: www.opensource.org/licenses/MIT

---

Made by [ScreenStaring](http://screenstaring.com)
