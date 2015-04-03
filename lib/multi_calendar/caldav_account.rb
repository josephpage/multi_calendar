require "multi_calendar/caldav"

module MultiCalendar
  class CaldavAccount

    attr_accessor :client

    attr_reader :username, :password, :server, :development

    def initialize params
      raise "Missing argument username" unless params[:username]
      raise "Missing argument password" unless params[:password]
      raise "Missing argument server" unless params[:server]
      @username = params[:username]
      @password = params[:password]
      @server = params[:server]
      @development = params[:development].present?
    end

    def list_calendars
      color_id = 0
      result =[]
      caldav_client.calendars.select{|cal|
        !(cal.path =~ /.ics\z/)
      }.each{ |cal|
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

      cals = caldav_client.calendars.select{|c| c.name && c.path}
      cals.select!{|cal| params[:calendar_ids].find_index cal.path}


      events = []
      cals.each do |cal|
        cal_events = cal.events({start_date: params[:start_date], end_date: params[:end_date]})
        cal_events.map!{ |ev|
          if ev.recurs?
            ev.occurrences({starting: params[:start_date], before: params[:end_date]})
          else
            ev
          end
        }.flatten!
        cal_events.each do |ev|
          events << build_event_hash_from_response(ev, cal.path)
        end
      end

      events
    end

    def get_event params
      cals = caldav_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      events = cal.events
      events = events.select{|ev| ev.uid == params[:event_id]}
      if events.length > 0
        build_event_hash_from_response(events[0], cal.path)
      else
        raise MultiCalendar::EventNotFoundException
      end
    end

    def create_event params
      cals = caldav_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.create_event event_data_from_params(params)
    end

    def update_event params
      cals = caldav_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.update_event event_data_from_params(params)
    end

    def delete_event params
      cals = caldav_client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.delete_event params[:event_id]
    end


    def credentials_valid?
      credentials_valid = true
      begin
        if caldav_client.calendars.select{|c| c.name && c.path}.empty?
          credentials_valid = false
        end
      rescue
        credentials_valid = false
      end

      credentials_valid
    end

    private

    def caldav_client
      @client ||= Caldav::Client.new(username, password, "jddv-proxy-#{@server}.herokuapp.com", @development)
    end

    def event_data_from_params params

      params[:start_date] = params[:start_date].to_time.utc.to_datetime
      params[:end_date] = params[:end_date].to_time.utc.to_datetime
      start_param = params[:start_date].strftime("%Y%m%dT%H%M%SZ")
      end_param = params[:end_date].strftime("%Y%m%dT%H%M%SZ")
      if params[:all_day]
        start_param = params[:start_date].strftime("%Y%m%d")
        end_param = params[:end_date].strftime("%Y%m%d")
      end

      {
          event_id: params[:event_id],
          summary: "#{params[:summary]}",
          start: start_param,
          end: end_param,
          attendees: (params[:attendees] || []).map{|att| att[:email]},
          description: "#{params[:description]}",
          location: "#{params[:location]}"
      }
    end

    def build_event_hash_from_response ev, calPath
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
          'htmlLink' => "#{ev.uid}",
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