# frozen_string_literal: true

module Hutch
  module Retry
    module Consumer
      module ClassMethods
        include Hutch::Logging

        def max_retries(counter)
          @max_retries = counter
        end

        def retry_on(array)
          @retry_on = array
        end

        def get_max_retries
          @max_retries || 5
        end

        def get_retry_on
          @retry_on || [StandardError]
        end

        def exp_backoff(retry_count)
          ((retry_count + 1)**4) + 30 + (retry_count + 2)
        end

        def retry_exchange_options(options = {})
          @retry_exchange_options = options
        end

        def retry_exchange_name
          (@retry_exchange_options || {}).fetch(:name, "#{get_queue_name}.retry")
        end

        def retry_exchange_durable?
          (@retry_exchange_options || {}).fetch(:durable, true)
        end
        alias retry_query_durable? retry_exchange_durable?

        def channel
          @broker.channel
        end

        def retry_exchange
          @retry_exchange ||= Hutch::Adapter.new_exchange(
            channel,
            "headers",
            retry_exchange_name,
            durable: retry_exchange_durable?
          )
        end

        def create_retry_queues!(broker)
          logger.info "setting up retry queues for #{retry_exchange_name} exchange"

          @broker = broker

          (0...get_max_retries)
            .map(&method(:exp_backoff))
            .each(&method(:create_retry_queue!))
        end

        def create_retry_queue!(delay)
          channel.queue(
            "#{retry_exchange_name}.#{delay}",
            durable: retry_query_durable?,
            arguments: {
              "x-dead-letter-exchange": @broker.exchange.name,
              "x-message-ttl": delay * 1_000
            }
          ).bind(retry_exchange, arguments: { "backoff-delay": delay, "x-match": "all" })
        end
      end

      def self.included(base)
        base.include(Hutch::Consumer)
        base.extend(ClassMethods)
      end
    end
  end
end
