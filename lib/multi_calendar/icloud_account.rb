require "multi_calendar/caldav"

module MultiCalendar
  class IcloudAccount

    attr_accessor :client

    attr_reader :username, :password, :development

    # Usage
    #
    #
    # icloud_account = MultiCalendar::IcloudAccount.new(
    #  username:     "$$USERNAME$$",
    #  password:     "$$PASSWORD$$"
    # )
    #
    # icloud_account.list_calendars
    #
    # icloud_account.list_events (
    #  start_date:   DateTime.now,
    #  end_date:     DateTime.now + 60,
    #  calendar_ids: ["$$CALENDAR-ID-1$$", "$$CALENDAR-ID-2$$"]
    # )
    #
    # icloud_account.get_event(
    #  calendar_id:  "$$CALENDAR-ID$$",
    #  event_id:     "$$EVENT-ID$$"
    # )
    #
    # icloud_account.create_event(
    #  calendar_id:  "$$CALENDAR-ID$$",
    #  start_date:   DateTime.now,
    #  end_date:     DateTime.now + 1,
    #  summary:      "New event",
    #  description:  "created by Multi-Calendar gem",
    #  attendees:    [{email: "you@yourdomain.com"}],
    #  location:     "Paris"
    # )
    #
    # icloud_account.update_event(
    #  calendar_id:  "$$CALENDAR-ID$$",
    #  event_id:     "$$EVENT-ID$$",
    #  start_date:   DateTime.now,
    #  end_date:     DateTime.now + 1,
    #  summary:      "New event",
    #  description:  "created by Multi-Calendar gem",
    #  attendees:    [{email: "you@yourdomain.com"}],
    #  location:     "Paris"
    # )
    # icloud_account.delete_event(
    #  calendar_id:  "$$CALENDAR-ID$$",
    #  event_id:     "$$EVENT-ID$$"
    # )
    #
    # icloud_account.credentials_valid?


    def initialize params
      raise "Missing argument username" unless params[:username]
      raise "Missing argument password" unless params[:password]
      @username = params[:username]
      @password = params[:password]
      @development = params[:development].present?
    end

    def list_calendars
      color_id = 0
      result =[]
      icloud_client.calendars.select{|c| c.name &&
          c.path &&
          !c.path.end_with?("/calendars/") &&
          !c.path.end_with?("/calendars/tasks/") &&
          !c.path.end_with?("/calendars/notification/")}.each{ |cal|
        color_id += 1
        result << {
            summary: cal.name,
            id: cal.path,
            colorId: color_id
        }
      }
      result
    end

    def list_events params
      cals = icloud_client.calendars.select{|c| c.name && c.path}
      cals.select!{|cal| params[:calendar_ids].find_index cal.path}

      events = []
      cals.each do |cal|
        cal_events = cal.events({start_date: params[:start_date], end_date: params[:end_date]})
        cal_events = cal_events.map{ |event_hash|
          if event_hash[:event].recurs?
            event_hash[:event].occurrences({starting: params[:start_date], before: params[:end_date]}).map{|ev|
              {
                  url: event_hash[:url],
                  event: ev,
                  occurrence: true
              }
            }
          else
            event_hash
          end
        }.flatten.group_by{|event_hash|
          event_hash[:event].recurrence_id || event_hash[:url]
        }.map{|k, event_hashes|
          if event_hashes.length == 1
            event_hashes[0]
          else
            event_hashes.sort_by{|event_hash| (event_hash[:occurrence])?1:0}.first
          end
        }
        cal_events.each do |event_hash|
          events << build_event_hash_from_response(event_hash[:event], event_hash[:url], cal.path)
        end
      end

      events
    end

    def get_event params
      cals = icloud_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first

      events = cal.get_event(params[:event_url])
      if events && events.length > 0
        events.map{|event|
          build_event_hash_from_response(event[:event], event[:url], cal.path)
        }.first
      else
        raise MultiCalendar::EventNotFoundException
      end
    end

    def create_event params
      cals = icloud_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.create_event event_data_from_params(params)
    end

    def update_event params
      cals = icloud_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.update_event event_data_from_params(params)
    end

    def delete_event params
      cals = icloud_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.delete_event params[:event_url]
    end

    def credentials_valid?
      credentials_valid = true
      begin
        if icloud_client.calendars.select{|c| c.name && c.path}.empty?
          credentials_valid = false
        end
      rescue
        credentials_valid = false
      end

      credentials_valid
    end

    private

    def icloud_client
      @client ||= Caldav::Client.new(username, password, "p01-caldav.icloud.com", development, true)
    end

    def event_data_from_params params
      if params[:all_day]
        start_param = params[:start_date].strftime("%Y%m%d")
        end_param   = params[:end_date].strftime("%Y%m%d")
        start_timezone = nil
        end_timezone = nil
      else
        start_param = params[:start_date].strftime("%Y%m%dT%H%M%S")
        end_param   = params[:end_date].strftime("%Y%m%dT%H%M%S")
        start_timezone = params[:start_timezone]
        end_timezone = params[:end_timezone]
      end

      {
          event_id: params[:event_id],
          event_url: params[:event_url],
          summary: "#{params[:summary]}",
          start: start_param,
          end: end_param,
          start_timezone: start_timezone,
          end_timezone: end_timezone,
          attendees: (params[:attendees] || []).map{|att| att[:email]},
          description: "#{params[:description]}",
          location: "#{params[:location]}"
      }
    end

    def build_event_hash_from_response ev, event_url, calPath
      attendees = ev.attendee_property.map{|att|
        {
            displayName: "#{att.params['NAME']}".gsub("\\\"", "\""),
            responseStatus: att.params['PARTSTAT'] || "Unknown",
            email: att.params['EMAIL'] || att.value.gsub("mailto:", "")
        }
      }
      if ev.organizer_property
        organizer_email = ev.organizer_property.params['EMAIL']
        organizer_already_here = false
        attendees.each do |att|
          if att[:email] == organizer_email
            organizer_already_here = true
            att[:organizer] = true
          end
        end
        unless organizer_already_here
          attendees << {
              displayName: "#{ev.organizer_property.params['NAME']}".gsub("\\\"", "\""),
              responseStatus: "Organizer",
              email: organizer_email
          }
        end
      end

      event_hash = {
          'id' => "#{ev.uid}",
          'summary' => "#{ev.summary}".gsub("\\\"", "\""),
          'location' => "#{ev.location}".gsub("\\\"", "\""),
          'description' => "#{ev.description}".gsub("\\\"", "\""),
          'attendees' => attendees,
          'htmlLink' => "#{event_url}",
          'calId' => calPath,
          'private' => false,
          'owned' => true
      }

      if ev.dtstart.class == DateTime
        event_hash['start'] = {
            'dateTime' => ev.dtstart.strftime("%FT%T%:z")
        }
        event_hash['end'] = {
            'dateTime' => ev.dtend.strftime("%FT%T%:z")
        }
        event_hash['all_day'] = false
      else
        event_hash['start'] = {
            'date' => ev.dtstart.strftime("%F")
        }
        event_hash['end'] = {
            'date' => ev.dtend.strftime("%F")
        }
        event_hash['all_day'] = true
      end

      event_hash
    end

  end
end


#To ensure ri_cal compatibility
class Time
  class << self
    define_method "get_zone" do |time_zone|
      return time_zone if time_zone.nil? || time_zone.is_a?(ActiveSupport::TimeZone)
      # lookup timezone based on identifier (unless we've been passed a TZInfo::Timezone)
      unless time_zone.respond_to?(:period_for_local)
        time_zone = ActiveSupport::TimeZone[time_zone] || TZInfo::Timezone.get(time_zone) rescue nil
      end
      # Return if a TimeZone instance, or wrap in a TimeZone instance if a TZInfo::Timezone
      if time_zone
        time_zone.is_a?(ActiveSupport::TimeZone) ? time_zone : ActiveSupport::TimeZone.create(time_zone.name, nil, time_zone)
      end
    end
  end
end