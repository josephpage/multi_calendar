require 'google/api_client'

module MultiCalendar
  class GoogleAccount

    attr_reader :access_token, :email, :refresh_token, :client_id, :client_secret

    # Usage
    #
    #
    # google_account = MultiCalendar::GoogleAccount.new(
    #  client_id:     "$$CLIENT-ID$$",
    #  client_secret: "$$CLIENT-SECRET$$",
    #  refresh_token: "$$USER-REFRESH-TOKEN$$"
    # )
    #
    # google_account.list_events (
    #  start_date:    DateTime.now,
    #  end_date:      DateTime.now + 60,
    #  calendar_ids:  ["$$CALENDAR-ID-1$$", "$$CALENDAR-ID-2$$"]
    # )
    #
    # google_account.get_event (
    #  calendar_id:   "$$CALENDAR-ID$$",
    #  event_id:      "$$EVENT-ID"
    # )
    #
    # google_account.share_calendar_with (
    #  calendar_id:   "$$CALENDAR-ID$$",
    #  email:         "email@mydomain.com"
    # )


    def initialize params
      raise "Missing argument client_id" unless params[:client_id]
      raise "Missing argument client_secret" unless params[:client_secret]
      raise "Missing argument refresh_token" unless params[:refresh_token]
      @client_id = params[:client_id]
      @client_secret = params[:client_secret]
      @email = params[:email]
      @refresh_token = params[:refresh_token]
    end

    def client
      unless @client
        @client = Google::APIClient.new(
            application_name: 'JulieDesk',
            application_version: '1.0.0'
        )
        @client.authorization.client_id = client_id
        @client.authorization.client_secret = client_secret
        @client.authorization.refresh_token = refresh_token
        @client.authorization.grant_type = 'refresh_token'
        @client.authorization.fetch_access_token!

        @access_token = client.authorization.access_token
      end
      @client
    end

    def service
      unless @service
        @service = client.discovered_api('calendar', 'v3')
      end
      @service
    end

    def refresh_access_token
      client.authorization.grant_type = 'refresh_token'
      #client.authorization.expires_at = self.expires_at.to_i
      client.authorization.fetch_access_token!

      @access_token = client.authorization.access_token
    end

    def list_calendars
      result = client.execute(
          :api_method => service.calendar_list.list,
          :headers => {'Content-Type' => 'application/json'})

      result.data['items'].map {|item|
        {
            id: item['id'],
            summary: item['summary'],
            colorId: item['colorId'],
            timezone: item['time_zone']
        }
      }
    end

    def list_events params
      total_result = []
      time_zone = nil
      params[:calendar_ids].each do |calendar_id|
        result = client.execute(
            :api_method => service.events.list,
            :parameters => {
                calendarId: calendar_id,
                timeMin: params[:start_date].strftime("%Y-%m-%dT%H:%M:%S%Z"),
                timeMax: params[:end_date].strftime("%Y-%m-%dT%H:%M:%S%Z"),
                singleEvents: true
            },
            :headers => {'Content-Type' => 'application/json'})

        time_zone ||= result.data['timeZone']

        if calendar_id == email
          time_zone = result.data['timeZone']
        end
        total_result += filter_items(result.data['items']).map { |item|
          build_event_hash_from_response(item, calendar_id)
        }
      end

      #{
      #    time_zone: time_zone,
      #    events: total_result
      #}
      total_result
    end

    def get_event params
      result = client.execute(
          :api_method => service.events.get,
          :parameters => {
              calendarId: params[:calendar_id],
              eventId: params[:event_id]
          },
          :headers => {'Content-Type' => 'application/json'})

      if result.data['error']
        if result.data['error']['message'] == "Not Found"
          raise MultiCalendar::EventNotFoundException
        end
        raise MultiCalendar::UnknownException
      end

      raise MultiCalendar::EventNotFoundException if result.data['status'] == "cancelled"

      build_event_hash_from_response result.data, params[:calendar_id]
    end

    def create_event params

      result = client.execute(
          :api_method => service.events.insert,
          :parameters => {
              calendarId: params[:calendar_id],
              sendNotifications: true,
          },
          :body_object => build_event_data_from_hash(params),
          :headers => {'Content-Type' => 'application/json'})

      {
          event_id: result.data.id,
          calendar_id: params[:calendar_id],
          event_url: ""
      }
    end

    def update_event params
      result = client.execute(
          :api_method => service.events.update,
          :parameters => {
              calendarId: params[:calendar_id],
              eventId: params[:event_id],
              sendNotifications: true
          },
          :body_object => build_event_data_from_hash(params),
          :headers => {'Content-Type' => 'application/json'})

      result.data.id
    end

    def delete_event params
      result = client.execute(
          :api_method => service.events.delete,
          :parameters => {
              calendarId: params[:calendar_id],
              eventId: params[:event_id],
              sendNotifications: true
          },
          :headers => {'Content-Type' => 'application/json'})

      result.body == ""
    end


    def share_calendar_with params
      client.execute(
          :api_method => service.acl.insert,
          :parameters => {
              calendarId: params[:calendar_id]
          },
          :body_object => {
              role: "writer",
              scope: {
                  type: "user",
                  value: params[:email]
              }
          },
          :headers => {'Content-Type' => 'application/json'})
    end

    private

    def filter_items items
      items.select{|item|
        me = item['attendees'].select{|attendee| attendee['self'] == true}.try(:first)
        !me || me['responseStatus'] != "declined"
      }
    end

    def generate_attendees_array attendees
      result = (attendees || []).map{|att|
        {
            email: att[:email]
        }
      }.select{|att|
        att[:email] != self.email
      }
      if result.length > 0
        result << {
            email: self.email,
            responseStatus: "accepted"
        }
      end

      result
    end

    def build_event_data_from_hash params
      start_param = {
            dateTime: params[:start_date].strftime("%Y-%m-%dT%H:%M:%S%Z")
      }
      end_param = {
          dateTime: params[:end_date].strftime("%Y-%m-%dT%H:%M:%S%Z")
      }

      if params[:all_day]
        start_param = {
            date: params[:start_date].strftime("%Y-%m-%d")
        }
        end_param = {
            date: params[:end_date].strftime("%Y-%m-%d")
        }
      end

      result = {
          start: start_param,
          end: end_param,
          summary: params[:summary],
          location: params[:location],
          visibility: (params[:private])?'private':'default',
          attendees: generate_attendees_array(params[:attendees]),
          description: params[:description]
      }
      if params[:recurrence].present?
        result[:recurrence] = params[:recurrence]
      end

      result
    end

    def build_event_hash_from_response data, calendar_id
      owned = false
      if data['organizer'] && data['organizer']['self']
        owned = true
      end

      start_hash = {
          'dateTime' => data['start']['dateTime']
      }
      end_hash = {
          'dateTime' => data['end']['dateTime']
      }
      unless data['start']['dateTime']
        start_hash = {
            'date' => data['start']['date']
        }
        end_hash = {
            'date' => data['end']['date']
        }
      end

      {
          'id' => data['id'],
          'summary' => "#{data['summary']}",
          'description' => "#{data['description']}",
          'location' => "#{data['location']}",
          'start' => start_hash,
          'end' => end_hash,
          'private' => data['visibility'] == 'private',
          'all_day' => data['start']['dateTime'].nil?,
          'owned' => owned,
          'attendees' => (data['attendees'] || []).map { |att| {email: att['email'], name: att['displayName']} },
          'calId' => calendar_id,
          'recurringEventId' => data['recurringEventId'],
          'recurrence' => (data['recurrence'] || []).map{|rrule| rrule.gsub("RRULE:", "")}
      }
    end
  end
end