# frozen_string_literal: true

require "hutch"
require_relative "retry/worker_extension"

module Hutch
  module Retry
    autoload :Consumer, ::File.expand_path(::File.dirname(__FILE__)) + "/retry/consumer"
    autoload :VERSION,  ::File.expand_path(::File.dirname(__FILE__)) + "/retry/version"
  end
end
