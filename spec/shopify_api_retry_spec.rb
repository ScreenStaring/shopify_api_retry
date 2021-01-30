require "shopify_api_retry"
require "minitest/autorun"

TestHTTPResponse = Struct.new(:code, :retry_after) do
  def [](name)
    name == "Retry-After" ? (retry_after || 2) : nil
  end
end

RATE_LIMITED = ActiveResource::ClientError.new(TestHTTPResponse.new("429"))
SERVER_ERROR = ActiveResource::ClientError.new(TestHTTPResponse.new("500"))
RETRY_OPTIONS = { "429" => { :tries => 2, :wait => 0 } }.freeze

describe ShopifyAPIRetry::Config do
  describe "#to_h" do
    it "returns a Hash based on the settings" do
      cfg = ShopifyAPIRetry::Config.new
      # Defaults
      _(cfg.to_h).must_equal("429" => { :tries => 2, :wait => nil })

      cfg.default_wait = 5
      cfg.default_tries = 10

      _(cfg.to_h).must_equal("429" => { :wait => 5, :tries => 10 })

      cfg.on "520", :wait => 2, :tries => 3
      cfg.on SocketError, :wait => 10, :tries => 5
      cfg.on [IOError, "SystemCallError"], :wait => 1, :tries => 1

      _(cfg.to_h).must_equal(
        "429" => { :wait => 5, :tries => 10 },
        "520" => { :wait => 2, :tries => 3 },
        "SocketError" => { :wait => 10, :tries => 5 },
        "IOError" => { :wait => 1, :tries => 1 },
        "SystemCallError" => { :wait => 1, :tries => 1 },
      )
    end
  end
end

describe ShopifyAPIRetry do
  describe ".configure" do
    it "sets the default retry options" do
      ShopifyAPIRetry.configure do |cfg|
        cfg.default_wait = 1
        cfg.default_tries = 2
        cfg.on "5XX", :wait => 3, :tries => 4
      end

      _(ShopifyAPIRetry.config.to_h).must_equal(
        "429" => { :wait => 1, :tries => 2 },
        "5XX" => { :wait => 3, :tries => 4 }
      )
    end
  end

  describe ".retry" do
    describe "when an HTTP status code is specified" do
      it "retries the block the specified number of times for that code" do
        runit = ->(n) do
          tried = 0

          begin
            ShopifyAPIRetry.retry "429" => { :tries => n, :wait => 0 }, "500" => { :tries => 5, :wait => 0 } do
              tried += 1
              raise RATE_LIMITED
            end
          rescue => e
            # Ignore, handle this in another test
            raise $! unless $!.message == RATE_LIMITED.message
          end

          tried
        end

        _(runit[1]).must_equal(1)
        _(runit[2]).must_equal(2)
      end

      it "re-raises the error when then reties exceed the specified limit" do
        e = _ {
          ShopifyAPIRetry.retry RETRY_OPTIONS do
            raise RATE_LIMITED
          end
        }.must_raise(ActiveResource::ClientError)

        _(e.message).must_match(/Response code = 429/)
      end
    end

    describe "when an HTTP status code prefix is specified" do
      it "retries the block the specified number of times for all error statuses that begin with the prefix" do
        options = { "5XX" => { :tries => 2, :wait => 0 } }
        tried = 0

        _ {
          ShopifyAPIRetry.retry options do
            tried += 1
            raise SERVER_ERROR
          end
        }.must_raise(ActiveResource::ClientError)

        _(tried).must_equal(2)

        tried = 0
        _ {
          ShopifyAPIRetry.retry options do
            tried += 1
            raise ActiveResource::ClientError.new(TestHTTPResponse.new("520"))
          end
        }.must_raise(ActiveResource::ClientError)

        _(tried).must_equal(2)
      end
    end

    describe "when an error is raised that's not in the retry list" do
      it "does not retry the block" do
        tried = 0

        begin
          ShopifyAPIRetry.retry SocketError => { :tries => 2, :wait => 0 }, :wait => 0, :tries => 5 do
            tried += 1
            raise "zOMG!@#"
          end
        rescue
          raise $! unless $!.message == "zOMG!@#"
        end

        _(tried).must_equal(1)
      end

      it "re-raises the error" do
        e = _ {
          ShopifyAPIRetry.retry SocketError => { :tries => 2, :wait => 0 } do
            raise "zOMG!@#"
          end
        }.must_raise(RuntimeError)

        _(e.to_s).must_equal("zOMG!@#")
      end
    end

    describe "when multiple errors are specified" do
      it "retries each according to its spec" do
        tried = 0
        options = RETRY_OPTIONS.merge(500 => { :tries => 3, :wait => 0 })

        begin
          ShopifyAPIRetry.retry options do
            tried += 1
            raise SERVER_ERROR
          end
        rescue
          raise $! unless $!.message == SERVER_ERROR.message
        end

        _(tried).must_equal(3)

        tried = 0

        begin
          ShopifyAPIRetry.retry options do
            tried += 1
            raise RATE_LIMITED
          end
        rescue
          raise $! unless $!.message == RATE_LIMITED.message
        end

        _(tried).must_equal(2)
      end

      it "waits according to its spec" do
        options = { 429 => { :tries => 2, :wait => 4 }, 500 => { :tries => 2, :wait => 2 } }
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          ShopifyAPIRetry.retry options do
            raise SERVER_ERROR
          end
        rescue
          raise $! unless $!.message == SERVER_ERROR.message
        end

        _(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).must_be_close_to(2, 0.5)

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          ShopifyAPIRetry.retry options do
            raise RATE_LIMITED
          end
        rescue
          raise $! unless $!.message == RATE_LIMITED.message
        end

        _(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).must_be_close_to(4, 0.5)
      end
    end

    describe "when no error is raised" do
      it "calls the block once" do
        tried = 0

        ShopifyAPIRetry.retry RETRY_OPTIONS do
          tried += 1
        end

        _(tried).must_equal(1)
      end
    end

    describe "when no arguments are given" do
      it "only retries HTTP 429s once" do
        tried = 0

        _ {
        ShopifyAPIRetry.retry do
          tried += 1
          raise RATE_LIMITED
        end
        }.must_raise(ActiveResource::ClientError)

        _(tried).must_equal(2)

        tried = 0

        _ {
          ShopifyAPIRetry.retry do
            tried += 1
            raise "No retry!"
          end
        }.must_raise(RuntimeError)


        _(tried).must_equal(1)
      end

      it "waits the amount of time given in the Retry-After header" do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          ShopifyAPIRetry.retry do
            raise ActiveResource::ClientError.new(TestHTTPResponse.new("429", 3))
          end
        rescue
          raise $! unless $!.message == RATE_LIMITED.message
        end

        _(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).must_be_close_to(3, 0.75)
      end
    end
  end
end
