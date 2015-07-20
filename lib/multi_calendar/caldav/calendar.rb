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
      @ical ||= Calendar.rical_parse_string(self.ical_data).first
    end

    def delete_event event_url
      res_code = self.client.delete(self.client.caldav_server, "#{event_url}", {}, "")
      res_code == "204"
    end

    def update_event params = {}
      create_or_update_event params.merge({mode: "update"})
    end

    def create_event params = {}
      create_or_update_event params.merge({mode: "create"})
    end

    def create_or_update_event params = {}
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




      if params[:mode] == "create"
        randomizator = ""
        res_code = "412"
        count = 0
        while res_code != "201" && count < 10
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
          event_url = "#{self.path}#{uid}.ics/"
          res_code = self.client.put(self.client.caldav_server, event_url, {"Content-Type" => "text/calendar", "If-None-Match" => "*"}, xml_request)
          randomizator = (0...10).map { (0..9).to_a[rand(10)]}.join
          count += 1
        end
        if res_code == "201" && params[:mode] == "create"
          {
              event_id: uid,
              calendar_id: self.path,
              event_url: event_url
          }
        else
          nil
        end
      elsif params[:mode] == "update"

        xml_request = <<END
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//CALENDARSERVER.ORG//NONSGML Version 1//EN
#{timezone_data}BEGIN:VEVENT
UID:#{params[:event_id]}
DTSTART#{start_timezone_data}:#{params[:start]}
DTEND#{end_timezone_data}:#{params[:end]}
SUMMARY:#{params[:summary]}
LOCATION:#{params[:location]}
DESCRIPTION:#{params[:description].gsub(/\n/, "\\n")}
#{attendees_str}
END:VEVENT
END:VCALENDAR
END

        res_code = self.client.put(self.client.caldav_server, "#{params[:event_url]}", {"Content-Type" => "text/calendar", "If-Match" => "*"}, xml_request)
        if res_code == "204" && params[:mode] == "update"
          {
              event_id: params[:event_id],
              calendar_id: self.path,
              event_url: params[:event_url]
          }
        else
          nil
        end
      else
        raise "Unknown mode"
      end

    end

    def events params={}
      start_date = params[:start_date]
      end_date = params[:end_date]

      if start_date || end_date
        start_date ||= DateTime.now - 100.years
        end_date ||= DateTime.now + 100.years
      end

      self.client.fetch_calendar_data(self.path, start_date, end_date).map{|event_hash|
        event_data = event_hash[:event_data].gsub(/\"(.*)\;(.*)\"/) { "#{$1}#{$2}" }
        if event_data
          event_data = Calendar.rical_parse_string(event_data)
        end
        if event_data && event_data.length > 0
         event_data.first.events.map{|event|
           {
               url: event_hash[:url],
               event: event
           }
         }
        else
          nil
        end

      }.flatten.compact
    end

    def get_event href
      xml_request  = <<END
        <c:calendar-multiget xmlns:d="DAV:"
        xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <c:calendar-data />
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR" />
          </c:filter>
          <d:href>#{href}</d:href>
        </c:calendar-multiget>
END
      xml = client.report(client.caldav_server, self.path, { "Depth" => 1 }, xml_request)

      if self.client.is_icloud
        responses = xml.css("response")
      else
        responses = xml.xpath("//d:response")
      end

      responses.map do |response|
        if self.client.is_icloud
          url = response.css("href").text
          event_data = response.css("prop *").text
        else
          url = response.xpath("//d:href").text
          event_data = response.xpath("//d:prop //*").text
        end

        if url
          if event_data
            event_data = event_data.gsub(/\"(.*)\;(.*)\"/) { "#{$1}#{$2}" }
          end
          if event_data
            event_data = Calendar.rical_parse_string(event_data)
          end
          if event_data && event_data.length > 0
            event_data.first.events.map do |event|
              {
                  url: url,
                  event: event
              }
            end
          else
            nil
          end
        else
          nil
        end
      end.flatten.compact
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

    def get_timezone_data timezones
      all_timezones = YAML.load_file(File.join(__dir__, "timezones.yml"))
      timezones.uniq.map{|timezone_id|
        timezone_data = all_timezones[timezone_id]
        raise "Unknown timezone: '#{timezone_id}'" unless timezone_data
        timezone_data
      }.join("\n")
    end

    def self.rical_parse_string str
      RiCal.parse_string(str.gsub("X-ADDRESS=;", ""))
    end
  end
end
