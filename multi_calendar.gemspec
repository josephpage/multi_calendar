Gem::Specification.new do |s|
  s.name        = 'multi_calendar'
  s.version     = '0.3.1.9'
  s.date        = '2015-02-17'
  s.summary     = "Multi Calendar"
  s.description = "A gem to rule them all"
  s.authors     = ["Nicolas Marlier"]
  s.email       = 'nmarlier@gmail.com'
  s.files       = ["lib/multi_calendar.rb",
                   "lib/multi_calendar/google_account.rb",
                   "lib/multi_calendar/icloud_account.rb",
                   "lib/multi_calendar/office_account.rb",
                   "lib/multi_calendar/exchange_account.rb",
                   "lib/multi_calendar/caldav_account.rb",

                   "lib/multi_calendar/caldav.rb",
                   "lib/multi_calendar/caldav/client.rb",
                   "lib/multi_calendar/caldav/calendar.rb",
                   "lib/multi_calendar/caldav/monkey.rb",
  ]
  s.license     = 'MIT'
  s.homepage    = 'https://github.com/NicolasMarlier/multi_calendar'

  # runtime dependencies
  s.add_dependency 'google-api-client'
  s.add_dependency 'ri_cal', '~> 0.8.8'
  s.add_dependency 'vcard', '~> 0.2.12'
  s.add_dependency 'actionview'
  s.add_dependency 'nokogiri'
  #s.add_dependency 'viewpoint_nico'

  # development dependencies
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 2.0"
  s.add_development_dependency "mocha", ">= 0.9"
  s.add_development_dependency "gem-release"
end