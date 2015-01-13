require_relative '../lib/multi_calendar'

require 'yaml'

require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.mock_framework = :rspec



end