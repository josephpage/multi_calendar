require "multi_calendar/google_account"
require "multi_calendar/icloud_account"
require "multi_calendar/office_account"
require "multi_calendar/caldav_account"

module MultiCalendar

  class EventNotFoundException < Exception
  end

  class UnknownException < Exception
  end

  class AccessExpiredException < Exception
  end
end