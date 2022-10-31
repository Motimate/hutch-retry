# Hutch retry

Hutch-retry is an extension for [hutch](https://github.com/ruby-amqp/hutch) framework. It allows consumers to reprocess failed messages using an exponential backoff algorithm.

## Requirements

- `hutch 1.1.1` - this library use monkey patch to add retry mechanism

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add hutch-retry

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install hutch-retry

## Usage

To use hutch-retry replace `Hutch::Consumer` with `Hutch::Retry::Consumer` in your class.

```ruby
class ExampleConsumer
  include Hutch::Retry::Consumer

  consume "hutch.example"
  max_retries 3
  retry_on [TimeoutError]
  retry_exchange_options name: "example.retry",
                         durable: false
end
```

| Option name                      | Default value      | Type    |
|----------------------------------|--------------------|---------|
| max_retries                      | 5                  | Integer |
| retry_on                         | [StandardError]    | Array   |
| retry_exchange_options[:name]    | <queue_name>.retry | String  |
| retry_exchange_options[:durable] | true               | Boolean |

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Motimate/hutch-retry.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
