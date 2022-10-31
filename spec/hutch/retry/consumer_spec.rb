# frozen_string_literal: true

RSpec.describe Hutch::Retry::Consumer do
  let(:consumer) do
    unless defined? RetryConsumer
      class RetryConsumer
        include Hutch::Retry::Consumer
        consume "hutch.test"
      end
    end
    RetryConsumer
  end

  let(:exchange) { double("Exchange", name: "default_ex") }
  let(:queue) { double("Queue") }
  let(:channel) { double("Channel", queue: queue) }
  let(:broker) { double("Broker", channel: channel, exchange: exchange) }

  before { allow(consumer).to receive(:broker) { broker } }

  describe ".max_retries" do
    around do |example|
      consumer.get_max_retries.then do |default_value|
        consumer.max_retries(1)
        example.run
        consumer.max_retries(default_value)
      end
    end

    it "overrides default retries" do
      expect(consumer.get_max_retries).to eq(1)
    end
  end

  describe ".retry_on" do
    around do |example|
      consumer.get_retry_on.then do |default_value|
        consumer.retry_on([NotImplementedError])
        example.run
        consumer.retry_on(default_value)
      end
    end

    it "overrides default errors" do
      expect(consumer.get_retry_on).to eq([NotImplementedError])
    end
  end

  describe ".exp_backoff" do
    it { expect(consumer.exp_backoff(0)).to eq(33) }
    it { expect(consumer.exp_backoff(1)).to eq(49) }
    it { expect(consumer.exp_backoff(2)).to eq(115) }
    it { expect(consumer.exp_backoff(3)).to eq(291) }
    it { expect(consumer.exp_backoff(4)).to eq(661) }
  end

  describe ".retry_exchange_options" do
    after { consumer.retry_exchange_options(nil) }

    it "overrides default errors" do
      consumer.retry_exchange_options(name: "test.retry", durable: false)
      expect(consumer.retry_exchange_name).to eq("test.retry")
      expect(consumer.retry_exchange_durable?).to eq(false)
    end
  end

  describe ".retry_exchange" do
    after { consumer.instance_variable_set(:@broker, nil) }

    it "creates a new exchange" do
      consumer.instance_variable_set(:@broker, broker)
      expect(Hutch::Adapter).to receive(:new_exchange).with(
        channel,
        "headers",
        consumer.retry_exchange_name,
        durable: consumer.retry_exchange_durable?
      )
      consumer.retry_exchange
    end
  end

  describe ".create_retry_queues!" do
    it "calls .create_retry_queue! for each delay interval" do
      consumer.max_retries(5)
      expect(consumer).to receive(:create_retry_queue!).exactly(5).times
      consumer.create_retry_queues!(broker)
    end
  end

  describe ".create_retry_queue!" do
    let(:retry_exchange) { double("Retry exchange") }

    before { allow(consumer).to receive(:retry_exchange) { retry_exchange }  }
    after { consumer.instance_variable_set(:@broker, nil) }

    it "creates a new queue" do
      consumer.instance_variable_set(:@broker, broker)
      expect(channel).to receive(:queue).with(
        "#{consumer.retry_exchange_name}.33",
        durable: consumer.retry_exchange_durable?,
        arguments: {
          "x-dead-letter-exchange": exchange.name,
          "x-message-ttl": 33_000
        }
      )
      expect(queue).to receive(:bind).with(
        retry_exchange,
        arguments: {
          "backoff-delay": 33,
          "x-match": "all"
        }
      )

      consumer.create_retry_queue!(33)
    end
  end
end
