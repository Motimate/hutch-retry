# frozen_string_literal: true

module Hutch
  module Retry
    module WorkerExtension
      def setup_queue(consumer)
        logger.info "setting up queue: #{consumer.get_queue_name}"

        queue = @broker.queue(consumer.get_queue_name, consumer.get_options)
        @broker.bind_queue(queue, consumer.routing_keys)

        consumer.create_retry_queues!(@broker) if consumer.include?(Hutch::Retry::Consumer)

        queue.subscribe(consumer_tag: unique_consumer_tag, manual_ack: true) do |*args|
          delivery_info, properties, payload = Hutch::Adapter.decode_message(*args)
          handle_message(consumer, delivery_info, properties, payload)
        end
      end

      def handle_message(consumer, delivery_info, properties, payload)
        serializer = consumer.get_serializer || Hutch::Config[:serializer]
        logger.debug {
          spec = serializer.binary? ? "#{payload.bytesize} bytes" : "#{payload}"
          "message(#{properties.message_id || '-'}): " +
          "routing key: #{delivery_info.routing_key}, " +
          "consumer: #{consumer}, " +
          "payload: #{spec}"
        }

        message = Message.new(delivery_info, properties, payload, serializer)
        consumer_instance = consumer.new.tap { |c| c.broker, c.delivery_info = @broker, delivery_info }
        with_tracing(consumer_instance).handle(message)
        @broker.ack(delivery_info.delivery_tag)
      rescue => ex
        if consumer.include?(Hutch::Retry::Consumer)
          handle_retry(consumer, delivery_info, properties, payload, ex)
        else
          acknowledge_error(delivery_info, properties, @broker, ex)
        end
        handle_error(properties, payload, consumer, ex)
      end

      def handle_retry(consumer, delivery_info, properties, payload, ex)
        case ex
        when *consumer.get_retry_on
          current_retry_count = (properties[:headers] || {}).fetch("backoff-delay-count", 0)

          if current_retry_count < consumer.get_max_retries
            logger.debug "Retry message_id=#{properties[:message_id]} counter=#{current_retry_count + 1}"

            @broker.ack(delivery_info.delivery_tag)
            consumer.retry_exchange.publish(
              payload,
              routing_key: delivery_info.routing_key,
              message_id: properties[:message_id],
              timestamp: Time.now.to_i,
              headers: {
                "backoff-delay": consumer.exp_backoff(current_retry_count),
                "backoff-delay-count": current_retry_count + 1
              }
            )
          else
            logger.debug "Max retries exceeded message_id=#{properties[:message_id]}"

            acknowledge_error(delivery_info, properties, @broker, ex)
          end
        else
          acknowledge_error(delivery_info, properties, @broker, ex)
        end
      end
    end
  end

  class Worker
    prepend ::Hutch::Retry::WorkerExtension
  end
end
