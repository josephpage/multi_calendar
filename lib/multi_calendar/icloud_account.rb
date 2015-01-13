require "multi_calendar/iclouddav"

module MultiCalendar
  class IcloudAccount

    attr_reader :username, :password

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
    end

    def list_calendars
      client = ICloud::Client.new(username, password)
      color_id = 0
      result =[]
      client.calendars.select{|c| c.name && c.path}.each{ |cal|
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
      client = ICloud::Client.new(username, password)
      cals = client.calendars.select{|c| c.name && c.path}
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
      client = ICloud::Client.new(username, password)
      cals = client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      events = cal.events
      events = events.select{|ev| ev.uid == params[:event_id]}
      if events.length > 0
        build_event_hash_from_response(events[0], cal.path)
      else
        nil
      end
    end

    def create_event params
      client = ICloud::Client.new(username, password)
      cals = client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.create_event({
                           summary: "#{params[:summary]}",
                           start: params[:start_date],
                           end: params[:end_date],
                           attendees: (params[:attendees] || []).map{|att| att[:email]},
                           description: "#{params[:description]}",
                           location: "#{params[:location]}"
                       })
    end

    def update_event params
      client = ICloud::Client.new(username, password)
      cals = client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.update_event({
                           event_id: params[:event_id],
                           summary: "#{params[:summary]}",
                           start: params[:start_date],
                           end: params[:end_date],
                           attendees: (params[:attendees] || []).map{|att| att[:email]},
                           description: "#{params[:description]}",
                           location: "#{params[:location]}"
                       })
    end

    def delete_event params
      client = ICloud::Client.new(username, password)
      cals = client.calendars.select{|c| c.name && c.path}
      cals = cals.select{|c| c.path == params[:calendar_id]}
      cal = cals.first
      cal.delete_event params[:event_id]
    end

    def credentials_valid?
      credentials_valid = true
      begin
        client = ICloud::Client.new(username, password)
        if client.calendars.select{|c| c.name && c.path}.empty?
          credentials_valid = false
        end
      rescue
        credentials_valid = false
      end

      credentials_valid
    end

    private

    def build_event_hash_from_response ev, calPath
      attendees = ev.attendee_property.map{|att|
        {
            displayName: att.params['NAME'] || "",
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
              displayName: ev.organizer_property.params['NAME'] || "",
              responseStatus: "Organizer",
              email: organizer_email
          }
        end
      end

      event_hash = {
          'id' => "#{ev.uid}".force_encoding('utf-8'),
          'summary' => "#{ev.summary}".force_encoding('utf-8'),
          'location' => "#{ev.location}".force_encoding('utf-8'),
          'description' => "#{ev.description}".force_encoding('utf-8'),
          'attendees' => attendees,
          'htmlLink' => "#{ev.uid}".force_encoding('utf-8'),
          'calId' => calPath
      }

      if ev.dtstart.class == DateTime
        event_hash['start'] = {
            dateTime: ev.dtstart.strftime("%FT%T%:z")
        }
        event_hash['end'] = {
            dateTime: ev.dtend.strftime("%FT%T%:z")
        }
      else
        event_hash['start'] = {
            date: ev.dtstart.strftime("%F")
        }
        event_hash['end'] = {
            date: ev.dtend.strftime("%F")
        }
      end

      event_hash
    end

  end
end