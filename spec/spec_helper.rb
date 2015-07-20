require_relative '../lib/multi_calendar'

require 'yaml'

require 'webmock/rspec'
WebMock.disable_net_connect!(:allow => [/p01-caldav.icloud.com/, /caldav.orange.fr/])

RSpec.configure do |config|
  config.mock_framework = :rspec
end