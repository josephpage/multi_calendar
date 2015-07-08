require "ri_cal"
require "date"

module Caldav
  class Calendar
    attr_reader :client, :path, :name, :ical, :ical_data

    def initialize(client, path, name)
      @client = client
      @path = path
      @name = name
    end

    def ical
      @ical ||= RiCal.parse_string(self.ical_data).first
    end

    def events params={}
      if params[:start_date] || params[:end_date]
        start_date = params[:start_date] || DateTime.now - 100.years
        end_date = params[:end_date] || DateTime.now + 100.years

        RiCal.parse_string(self.ical_data(start_date, end_date)).first.events
      else
        self.ical.events
      end
    end

    def update_event params = {}
      raise "Missing start param" unless params[:start]
      raise "Missing end param" unless params[:end]


      attendees_str = ""
      attendees_str += (params[:attendees] || []).select{|attendee|
        attendee != self.client.email
      }.map{|attendee|
        <<END
ATTENDEE;PARTSTAT=NEEDS-ACTION;ROLE=REQ-PARTICIPANT;RSVP=TRUE:mailto:#{attendee}
END
      }.join("\n")

      unless attendees_str.blank?
        attendees_str += <<END
ORGANIZER;CN=Organizer:mailto:#{self.client.email}
ATTENDEE;CN=Organizer:mailto:#{self.client.email}
END
      end

      xml_request = <<END
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//CALENDARSERVER.ORG//NONSGML Version 1//EN
BEGIN:VEVENT
UID:#{params[:event_id]}
DTSTART:#{params[:start]}
DTEND:#{params[:end]}
SUMMARY:#{params[:summary]}
LOCATION:#{params[:location]}
SEQUENCE:0
DESCRIPTION:#{params[:description].gsub(/\n/, "\\n")}
#{attendees_str}
END:VEVENT
END:VCALENDAR
END
      res_code = self.client.put("#{self.path}#{params[:event_id]}.ics", {"Content-Type" => "text/calendar"}, xml_request)


      res_code == "200"
    end

    def create_event params = {}
      raise "Missing start param" unless params[:start]
      raise "Missing end param" unless params[:end]

      start_timezone_data = ""
      end_timezone_data   = ""
      timezone_data = ""
      if params[:start_timezone]
        params[:end_timezone] ||= params[:start_timezone]
        timezone_data = get_timezone_data([params[:start_timezone], params[:end_timezone]]) + "\n"
        start_timezone_data = ";TZID=#{params[:start_timezone]}"
        end_timezone_data = ";TZID=#{params[:end_timezone]}"
      end

      attendees_str = ""
      attendees_str += (params[:attendees] || []).select{|attendee|
        attendee != self.client.email
      }.map{|attendee|
        <<END
ATTENDEE;PARTSTAT=NEEDS-ACTION;ROLE=REQ-PARTICIPANT;RSVP=TRUE:mailto:#{attendee}
END
      }.join("\n")

      unless attendees_str.blank?
        attendees_str += <<END
ORGANIZER;CN=Organizer:mailto:#{self.client.email}
ATTENDEE;CN=Organizer:mailto:#{self.client.email}
END
      end


      randomizator = ""
      res_code = "412"
      while res_code == "412"
        uid = "#{params[:start]}-#{randomizator}"
        xml_request = <<END
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//CALENDARSERVER.ORG//NONSGML Version 1//EN
#{timezone_data}BEGIN:VEVENT
UID:#{uid}
DTSTART#{start_timezone_data}:#{params[:start]}
DTEND#{end_timezone_data}:#{params[:end]}
SUMMARY:#{params[:summary]}
LOCATION:#{params[:location]}
DESCRIPTION:#{params[:description].gsub(/\n/, "\\n")}
#{attendees_str}
END:VEVENT
END:VCALENDAR
END
        event_url = "#{self.path}#{uid}.ics"
        res_code = self.client.put(event_url, {"Content-Type" => "text/calendar", "If-None-Match" => "*"}, xml_request)
        randomizator = (0...10).map { (0..9).to_a[rand(10)]}.join
      end
      if res_code == "201"
        {
            event_id: uid,
            calendar_id: self.path,
            event_url: event_url
        }
      else
        nil
      end
    end

    def url
      "https://#{self.client.caldav_server}:#{self.client.port}#{path}"
    end

    def ical_data start_date=nil, end_date=nil
      # try to combine all separate calendars into one by removing VCALENDAR
      # headers
      if start_date && end_date
        @ical_data = nil
      else
        return @ical_data if @ical_data
      end
      ical_data_to_set = "BEGIN:VCALENDAR\n" <<
          self.client.fetch_calendar_data(self.path, start_date, end_date).split("\n").map{|line|
            if line.strip == "BEGIN:VCALENDAR" || line.strip == "END:VCALENDAR"
              next
            else
              line + "\n"
            end
          }.join <<
          "END:VCALENDAR\n"

      if start_date && end_date
        ical_data_to_set
      else
        @ical_data = ical_data_to_set
      end

    end
  end
end
