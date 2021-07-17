# Shopify API Retry

![CI](https://github.com/ScreenStaring/shopify_api_retry/workflows/CI/badge.svg)

Simple Ruby module to retry a [`ShopifyAPI` request](https://github.com/Shopify/shopify_api) if rate-limited or other errors
occur. Works with the REST and GraphQL APIs.

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

### REST API

By default requests are retried when a Shopify rate limit error (HTTP 429) is returned. The retry happens once after waiting for
[the seconds given by the HTTP `Retry-After` header](https://shopify.dev/concepts/about-apis/rate-limits):
```rb
require "shopify_api_retry" # requires "shopify_api" for you

ShopifyAPIRetry::REST.retry { customer.update_attribute(:tags, "foo") }
customer = ShopifyAPIRetry::REST.retry { ShopifyAPI::Customer.find(id) }
```

You can override this:
```rb
ShopifyAPIRetry::REST.retry(:wait => 3, :tries => 5) { customer.update_attribute(:tags, "foo")  }
```
This will try the request 5 times, waiting 3 seconds between each attempt. If a retry fails after the given number
of `:tries` the last error will be raised.

You can also retry requests when other errors occur:
```rb
ShopifyAPIRetry::REST.retry "5XX" => { :wait => 10, :tries => 2 } do
  customer.update_attribute(:tags, "foo")
end
```
This still retries rate limit requests, but also all HTTP 5XX errors.

Classes can be specified too:
```rb
ShopifyAPIRetry::REST.retry SocketError => { :wait => 1, :tries => 5 } do
  customer.update_attribute(:tags, "foo")
end
```

You can also set [global defaults](#global-defaults).

### GraphQL API

By default a retry attempt is made when your [GraphQL request is rate-limited](https://shopify.dev/concepts/about-apis/rate-limits#graphql-admin-api-rate-limits).
In order to calculate the proper amount of time to wait before retrying you must set the `X-GraphQL-Cost-Include-Fields` header
(_maybe this library should do this?_):

```rb
require "shopify_api_retry" # requires "shopify_api" for you

ShopifyAPI::Base.headers["X-GraphQL-Cost-Include-Fields"] = "true"
```

Once this is set run your queries and mutations and rate-limited requests will be retried.
The retry happens once, calculating the wait time from the API's cost data:
```rb
result = ShopifyAPIRetry::GraphQL.retry { ShopifyAPI::GraphQL.client.query(YOUR_QUERY) }
p result.data.whatever
```

To calculate the retry time **the query's return value must be returned by the block**.

You can override the retry times:
```rb
result = ShopifyAPIRetry::GraphQL.retry(:wait => 4, :tries => 4) do
  ShopifyAPI::GraphQL.client.query(YOUR_QUERY)
end
p result.data.whatever
```

Like retry attempts made with the REST API you can specify errors to retry but, due to the GraphQL specification, these must not
be HTTP status codes and are only relevant to network connection-related errors:

```rb
result = ShopifyAPIRetry::GraphQL.retry SocketError => { :wait => 1, :tries => 5 } do
  ShopifyAPI::GraphQL.client.query(YOUR_QUERY)
end
```

To give wait and try times for specifically for rate limit errors, use the key `:graphql`:
```rb
result = ShopifyAPIRetry::GraphQL.retry :graphql => { :wait => 10, :tries => 5 } do
  ShopifyAPI::GraphQL.client.query(YOUR_QUERY)
end
```

Note that specifying a `:wait` via `:graphql` or without an error key will skip calculating the retry based on the API
response's cost data.

### Global Defaults

You can configure global defaults to be used by REST and GraphQL calls. For example:

```rb
ShopifyAPIRetry.configure do |config|
  config.default_wait  = 2.5
  config.default_tries = 10

  # Use default_* for these
  config.on ["5XX", Net::ReadTimeout]

  config.on SocketError, :tries => 2, :wait => 1
end
```

## License

Released under the MIT License: www.opensource.org/licenses/MIT

---

Made by [ScreenStaring](http://screenstaring.com)
