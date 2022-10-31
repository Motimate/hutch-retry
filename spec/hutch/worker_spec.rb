# frozen_string_literal: true

RSpec.describe Hutch::Worker do
  let(:broker) { Hutch::Broker.new }
  let(:consumer) do
    class RetryConsumer
      include Hutch::Retry::Consumer
      consume "hutch.test"
      max_retries 1
      retry_on [NotImplementedError]
    end
    RetryConsumer
  end

  subject(:worker) { described_class.new(broker, [consumer], []) }

  describe "#setup_queue" do
    let(:queue) { double("Queue", bind: nil, subscribe: nil) }

    before { allow(broker).to receive_messages(queue: queue, bind_queue: nil) }

    it "creates delayed queues" do
      expect(consumer).to receive(:create_retry_queues!).with(broker)
      worker.setup_queue(consumer)
    end

    context "original behaviour" do
      before { allow(consumer).to receive(:create_retry_queues!) }

      it "creates a queue" do
        expect(broker).to receive(:queue).with(consumer.get_queue_name, consumer.get_options).and_return(queue)
        worker.setup_queue(consumer)
      end

      it "binds the queue to each of the routing keys" do
        expect(broker).to receive(:bind_queue).with(queue, Set.new(["hutch.test"]))
        worker.setup_queue(consumer)
      end

      it "sets up a subscription" do
        expect(queue).to receive(:subscribe).with(consumer_tag: %r(^hutch\-.{36}$), manual_ack: true)
        worker.setup_queue(consumer)
      end

      context "with a configured consumer tag prefix" do
        before { Hutch::Config.set(:consumer_tag_prefix, "appname") }

        it "sets up a subscription with the configured tag prefix" do
          expect(queue).to receive(:subscribe).with(consumer_tag: %r(^appname\-.{36}$), manual_ack: true)
          worker.setup_queue(consumer)
        end
      end

      context "with a configured consumer tag prefix that is too long" do
        let(:maximum_size) { 255 - SecureRandom.uuid.size - 1 }

        before { Hutch::Config.set(:consumer_tag_prefix, "a".*(maximum_size + 1)) }

        it "raises an error" do
          expect { worker.setup_queue(consumer) }.to raise_error(/Tag must be 255 bytes long at most/)
        end
      end
    end
  end

  describe "#handle_message" do
    let(:payload) { "{}" }
    let(:consumer_instance) { double("Consumer instance") }
    let(:delivery_info) { double("Delivery Info", routing_key: "test", delivery_tag: "dt") }
    let(:properties) { double("Properties", message_id: "uuid", content_type: "application/json") }

    before do
      allow(consumer).to receive_messages(new: consumer_instance)
      allow(broker).to receive(:ack)
      allow(broker).to receive(:nack)
      allow(consumer_instance).to receive(:broker=)
      allow(consumer_instance).to receive(:delivery_info=)
    end

    context "when the retry consumer fails" do
      it "calls #handle_retry" do
        allow(consumer_instance).to receive(:process).and_raise("failed")
        expect(worker).to receive(:handle_retry)
        worker.handle_message(consumer, delivery_info, properties, payload)
      end
    end

    context "original behaviour" do
      let(:consumer) do
        double("Consumer", get_queue_name: "consumer",
               get_arguments: {}, get_options: {}, get_serializer: nil,
               routing_keys: %w(test), include?: false)
      end

      it "passes the message to the consumer" do
        expect(consumer_instance).to receive(:process).with(an_instance_of(Hutch::Message))
        worker.handle_message(consumer, delivery_info, properties, payload)
      end

      it "acknowledges the message" do
        allow(consumer_instance).to receive(:process)
        expect(broker).to receive(:ack).with(delivery_info.delivery_tag)
        worker.handle_message(consumer, delivery_info, properties, payload)
      end

      context "when the consumer fails and a requeue is configured" do
        let(:requeuer) { double }

        it "requeues the message" do
          allow(consumer_instance).to receive(:process).and_raise("failed")
          allow(requeuer).to receive(:handle) { |delivery_info, _properties, broker, _e|
            broker.requeue delivery_info.delivery_tag
            true
          }
          allow(worker).to receive(:error_acknowledgements).and_return([requeuer])
          expect(broker).to_not receive(:ack)
          expect(broker).to_not receive(:nack)
          expect(broker).to receive(:requeue)

          worker.handle_message(consumer, delivery_info, properties, payload)
        end
      end

      context "when the consumer raises an exception" do
        before { allow(consumer_instance).to receive(:process).and_raise("a consumer error") }

        it "logs the error" do
          Hutch::Config[:error_handlers].each do |backend|
            expect(backend).to receive(:handle)
          end
          worker.handle_message(consumer, delivery_info, properties, payload)
        end

        it "rejects the message" do
          expect(broker).to receive(:nack).with(delivery_info.delivery_tag)
          worker.handle_message(consumer, delivery_info, properties, payload)
        end
      end

      context "when the payload is not valid json" do
        let(:payload) { "Not Valid JSON" }

        it "logs the error" do
          Hutch::Config[:error_handlers].each do |backend|
            expect(backend).to receive(:handle)
          end
          worker.handle_message(consumer, delivery_info, properties, payload)
        end

        it "rejects the message" do
          expect(broker).to receive(:nack).with(delivery_info.delivery_tag)
          worker.handle_message(consumer, delivery_info, properties, payload)
        end
      end
    end
  end

  describe "#handle_retry" do
    let(:retry_exchange) { double("Retry exchange") }
    let(:delivery_info) { double("Delivery Info", routing_key: "test", delivery_tag: "dt") }
    let(:properties) { Bunny::MessageProperties.new(message_id: "uuid", headers: {}) }
    let(:payload) { "{}" }
    let(:ex) { NotImplementedError.new }

    before do
      allow(consumer).to receive(:retry_exchange) { retry_exchange }
    end

    context "when not retriable error" do
      let(:ex) { NoMethodError.new }

      it "rejects message" do
        expect(broker).to receive(:nack).with(delivery_info.delivery_tag)
        worker.handle_retry(consumer, delivery_info, properties, payload, ex)
      end
    end

    context "when retriable error" do
      let(:time_now) { Time.parse("2030-01-01") }

      before { Timecop.freeze(time_now) }

      after { Timecop.return }

      context "when retries are not exceeded" do
        it "acknowledges the message and publishes to delayed queue" do
          expect(broker).to receive(:ack).with(delivery_info.delivery_tag)
          expect(retry_exchange).to receive(:publish).with(payload, {
            routing_key: "test",
            message_id: "uuid",
            timestamp: time_now.to_i,
            headers: {
              "backoff-delay": 33,
              "backoff-delay-count": 1
            }
          })
          worker.handle_retry(consumer, delivery_info, properties, payload, ex)
        end
      end

      context "when retries exceeded" do
        let(:properties) { Bunny::MessageProperties.new(message_id: "uuid", headers: { "backoff-delay-count" => 1 }) }

        it "rejects message" do
          expect(broker).to receive(:nack).with(delivery_info.delivery_tag)
          worker.handle_retry(consumer, delivery_info, properties, payload, ex)
        end
      end
    end
  end
end
