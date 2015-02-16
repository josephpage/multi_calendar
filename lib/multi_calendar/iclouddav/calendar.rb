require "ri_cal"
require "date"

module ICloud
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

    def delete_event event_id
      res_code = self.client.delete(self.client.caldav_server, "#{self.path}#{event_id}.ics/", {}, "")
      res_code == "204"
    end

    def update_event params = {}
      raise "Missing start param" unless params[:start]
      raise "Missing end param" unless params[:end]


      attendees_str = ""
      attendees_str += (params[:attendees] || []).map{|attendee|
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
DTSTART:#{params[:start].to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}
DTEND:#{params[:end].to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}
SUMMARY:#{params[:summary]}
LOCATION:#{params[:location]}
DESCRIPTION:#{params[:description].gsub(/\n/, "\\n")}
#{attendees_str}
END:VEVENT
END:VCALENDAR
END
      res_code = self.client.put(self.client.caldav_server, "#{self.path}#{params[:event_id]}.ics/", {"Content-Type" => "text/calendar", "If-Match" => "*"}, xml_request)


      res_code == "204"
    end
    
    def create_event params = {}
      raise "Missing start param" unless params[:start]
      raise "Missing end param" unless params[:end]

      attendees_str = ""
      attendees_str += (params[:attendees] || []).map{|attendee|
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
        uid = "#{params[:start].to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}-#{randomizator}"
        xml_request = <<END
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//CALENDARSERVER.ORG//NONSGML Version 1//EN
BEGIN:VEVENT
UID:#{uid}
DTSTART:#{params[:start].to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}
DTEND:#{params[:end].to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}
SUMMARY:#{params[:summary]}
LOCATION:#{params[:location]}
DESCRIPTION:#{params[:description].gsub(/\n/, "\\n")}
#{attendees_str}
END:VEVENT
END:VCALENDAR
END
        res_code = self.client.put(self.client.caldav_server, "#{self.path}#{uid}.ics/", {"Content-Type" => "text/calendar", "If-None-Match" => "*"}, xml_request)
        randomizator = (0...10).map { (0..9).to_a[rand(10)]}.join
      end
      if res_code == "201"
        uid
      else
        nil
      end
    end

    def get_event event_id
      xml_request = <<END
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data>
      <C:comp name="VCALENDAR">
        <C:prop name="VERSION"/>
        <C:comp name="VEVENT">
          <C:prop name="SUMMARY"/>
          <C:prop name="UID"/>
          <C:prop name="DTSTART"/>
          <C:prop name="DTEND"/>
          <C:prop name="DURATION"/>
          <C:prop name="RRULE"/>
          <C:prop name="RDATE"/>
          <C:prop name="EXRULE"/>
          <C:prop name="EXDATE"/>
          <C:prop name="RECURRENCE-ID"/>
        </C:comp>
        <C:comp name="VTIMEZONE"/>
      </C:comp>
    </C:calendar-data>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:prop-filter name="SUMMARY">
          <C:text-match>TTT – Runners Billin789g</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>
END
      self.client.report_without_xml_parsing(self.client.caldav_server, self.path, { "Depth" => 1 }, xml_request)
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

    def to_remind
      out = ""

      self.events.each do |ev|
        start = ev.dtstart.to_time.getlocal
        finish = ev.dtend.to_time.getlocal

        out << "REM "

        # remind doesn't support * operator for months or years, so rather than
        # repeat those below, we repeat them here by omitting the month and
        # year (monthly) or year to let remind repeat them
        if ev.rrule.any? && ev.rrule_property[0].freq == "MONTHLY"
          out << start.strftime("%-d %Y")
        elsif ev.rrule.any? && ev.rrule_property[0].freq == "YEARLY"
          out << start.strftime("%b %-d")
        else
          out << start.strftime("%b %-d %Y")
        end

        # to repeat events, remind needs an end date
        if ev.bounded?
          last = ev.occurrences.last.dtend

          if start.strftime("%Y%m%d") != last.strftime("%Y%m%d")
            out << " UNTIL " << last.strftime("%b %-d %Y")
          end

          # TODO: even if it's not bounded, we can manually repeat it in the
          # remind file for a reasonable duration, assuming we're getting
          # rebuilt every so often
        end

        if ev.rrule.any?
          # rrule_property
          # => [:FREQ=MONTHLY;UNTIL=20110511;INTERVAL=2;BYMONTHDAY=12]

          interval = ev.rrule_property.first.interval.to_i
          case ev.rrule_property.first.freq
          when "DAILY"
            out << " *#{interval}"
          when "WEEKLY"
            out << " *#{interval * 7}"
          when "MONTHLY", "YEARLY"
            # handled above
          else
            STDERR.puts "need to support #{ev.rrule_property.first.freq} freq"
          end
        end

        if ev.dtstart.class == DateTime
          out << " AT " << start.strftime("%H:%M")

          if (secs = finish.to_i - start.to_i) > 0
            hours = secs / 3600
            mins = (secs - (hours * 3600)) / 60
            out << " DURATION #{hours}:#{mins}"
          end
        end

        if ev.alarms.any? &&
        m = ev.alarms.first.trigger.match(/^([-\+])PT?(\d+)([WDHMS])/)
          tr_mins = m[2].to_i
          tr_mins *= case m[3]
            when "W"
              60 * 60 * 24 * 7
            when "D"
              60 * 60 * 24
            when "H"
              60 * 60
            when "S"
              (1.0 / 60)
            else
              1
            end

          tr_mins = tr_mins.ceil

          # remind only supports advance warning in days, so if it's smaller
          # than that, don't bother
          if tr_mins >= (60 * 60 * 24)
            days = tr_mins / (60 * 60 * 24)

            # remind syntax is flipped
            if m[1] == "-"
              out << " +#{days}"
            else
              out << " -#{days}"
            end
          end
        end

        out << " MSG "

        # show date, time, and location outside of %" quotes so that clients
        # like tkremind don't also include them on their default view

        # Monday the 1st
        out << "%w the %d%s"

        # at 12:34
        if ev.dtstart.class == DateTime
          out << " %3"
        end

        out << ": %\"" << ev.summary.gsub("%", "%%").gsub("\n", "%_") << "%\""

        if ev.location.present?
          out << " (at " << ev.location.gsub("%", "%%").gsub("\n", "%_") << ")"
        end

        # suppress extra blank line
        out << "%\n"
      end

      out
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
