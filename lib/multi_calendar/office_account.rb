require 'action_view'

OFFICE_API_HOST = "outlook.office365.com"
OFFICE_API_PORT = 443
OFFICE_READ_TIMEOUT = 10

module MultiCalendar
  class OfficeAccount

    include ActionView::Helpers::TextHelper
    include ERB::Util

    attr_reader :refresh_token, :client_id, :client_secret

    # Usage:
    #
    #
    # office_account = MultiCalendar::OfficeAccount.new(
    #  client_id:     "$$CLIENT-ID$$",
    #  client_secret: "$$CLIENT-SECRET$$",
    #  refresh_token: "$$USER-REFRESH-TOKEN$$"
    # )
    #
    # office_account.list_calendars
    #
    # office_account.list_events (
    #  start_date:  DateTime.now,
    #  end_date:    DateTime.now + 60,
    #  calendar_id: "$$CALENDAR-ID$$" || nil
    # )
    #
    # office_account.get_event(
    #  event_id:    "$$EVENT-ID$$"
    # )
    #
    # office_account.create_event(
    #  calendar_id: "$$CALENDAR-ID$$"
    #  start_date: DateTime.now,
    #  end_date: DateTime.now + 1,
    #  summary: "New event",
    #  description: "created by Multi-Calendar gem",
    #  attendees: [{email: "you@yourdomain.com"}],
    #  location: "Paris"
    # )
    #
    # office_account.update_event(
    #  event_id:    "$$EVENT-ID$$"
    #  start_date: DateTime.now + 2,
    #  end_date: DateTime.now + 3,
    #  summary: "Updated event",
    #  description: "updated by Multi-Calendar gem",
    #  attendees: [{email: "anotherone@yourdomain.com"}],
    #  location: "London"
    # )
    #
    # office_account.delete_event(
    #  event_id:    "$$EVENT-ID$$"
    # )

    # Notes:
    #
    #
    # The Office365 is relatively new and is very often responding in 30s or even more.
    # Especially, the 'list_calendars' call is extremely slow.
    # For 'list_events' and 'get_event' calls, a timeout of 10s as been added to the call.
    # These methods are going to respond nil if the timeout is reached ;
    # I advise to retry these calls until they respond (up to 3-4 times average)


    def initialize params
      raise "Missing argument client_id" unless params[:client_id]
      raise "Missing argument client_secret" unless params[:client_secret]
      raise "Missing argument refresh_token" unless params[:refresh_token]
      @client_id     = params[:client_id]
      @client_secret = params[:client_secret]
      @refresh_token = params[:refresh_token]
    end

    def access_token
      unless @access_token
        @access_token = refresh_access_token
      end
      @access_token
    end


    def refresh_access_token
      uri = URI('https://login.windows.net/common/oauth2/token')
      req = Net::HTTP::Post.new(uri.path)
      data = {
          grant_type: "refresh_token",
          refresh_token: refresh_token,
          client_id: client_id,
          client_secret: client_secret,
          resource: "https://outlook.office365.com"
      }
      req.form_data = data
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) {|http| http.request(req) }

      hash_res = JSON.parse(res.body)
      @access_token = hash_res['access_token']
    end

    def list_calendars
      res = make_office_api_request(
          method: Net::HTTP::Get,
          path: "/api/v1.0/me/calendars",
      )

      color_id = 0
      result = []

      JSON.parse(res.body)['value'].each do |hash|
        color_id += 1

        result << {
            id: hash['Id'],
            summary: hash['Name'],
            colorId: color_id
        }
      end

      result
    end

    def list_events params
      items = []
      params[:calendar_ids].each do |calendar_id|

        count = 50
        skip_count = 0
        while count == 50
          query_params = {
              "startDateTime" => "#{params[:start_date].strftime("%FT%T")}Z",
              "endDateTime" => "#{params[:end_date].strftime("%FT%T")}Z",
              "$top" => 50,
              "$skip" => skip_count
          }
          query_params_str = ""
          query_params.each do |k, v|
            query_params_str += "&#{k}=#{v}"
          end
          res = make_office_api_request(
              method: Net::HTTP::Get,
              path: "/api/v1.0/me/calendars/#{calendar_id}/calendarview?#{query_params_str}",
              timeout: OFFICE_READ_TIMEOUT
          )

          count = JSON.parse(res.body)['value'].length
          skip_count += 50

          JSON.parse(res.body)['value'].each do |ev|
            items << build_event_hash_from_response(ev, calendar_id)
          end
        end
      end

      items
    end

    def get_event params
      res = make_office_api_request(
          method: Net::HTTP::Get,
          path: "/api/v1.0/me/events/#{params[:event_id]}",
          timeout: OFFICE_READ_TIMEOUT
      )

      ev = JSON.parse(res.body)
      build_event_hash_from_response(ev, "")
    end

    def create_event params
      res = make_office_api_request(
          method: Net::HTTP::Post,
          path: "/api/v1.0/me/calendars/#{params[:calendar_id]}/events",
          body: format_event_data(params).to_json
      )

      if res.code == "201"
        JSON.parse(res.body)['Id']
      else
        nil
      end
    end

    def update_event params
      res = make_office_api_request(
          method: Net::HTTP::Patch,
          path: "/api/v1.0/me/events/#{params[:event_id]}",
          body: format_event_data(params).to_json
      )

      res.code == "200"
    end

    def delete_event params
      res = make_office_api_request(
          method: Net::HTTP::Delete,
          path: "/api/v1.0/me/events/#{params[:event_id]}"
      )
      res.code == "204"
    end

    private

    def format_text_as_html text
      h(simple_format(text))
    end

    def format_event_data params
      {
          "Subject" => params[:summary],
          "Body" => {
              "ContentType" => "HTML",
              "Content" => format_text_as_html("#{params[:description]}")
          },
          "Start" => params[:start_date].strftime(),
          "End" => params[:end_date].strftime(),
          "Location" => {"DisplayName" => params[:location]},
          "Attendees" => (params[:attendees] || []).map { |attendee|
            {
                "EmailAddress" => {
                    "Address" => attendee[:email]
                },
                "Type" => "Required"
            }
          }
      }
    end

    def make_office_api_request params
      req = params[:method].new(params[:path], {'Content-Type' =>'application/json'})
      req.add_field("Authorization", "Bearer #{access_token}")
      req.body = params[:body]
      Net::HTTP.start(OFFICE_API_HOST, OFFICE_API_PORT, use_ssl: true, read_timeout: params[:timeout]) {|http| http.request(req) }
    end

    def build_event_hash_from_response ev, calendar_id
      attendees = (ev['Attendees'] || []).map{|att|
        result = nil
        if att['EmailAddress']
          result = {
              displayName: "#{att['EmailAddress']['Name']}",
              email: "#{att['EmailAddress']['Address']}"
          }
          if att['Status']
            result[:responseStatus] = "#{att['Status']['Response']}"
          end
        end
        result
      }.compact

      event_hash = {
          'id' => "#{ev['Id']}",
          'summary' => "#{ev['Subject']}",
          'description' => "#{ev['BodyPreview']}",
          'attendees' => attendees,
          'htmlLink' => "#{ev['Id']}",
          'calId' => calendar_id,
          'private' => false,
          'owned' => true

      }

      if ev['Location'] && ev['Location']['DisplayName']
        event_hash['location'] = ev['Location']['DisplayName']
      end


      if ev['IsAllDay']
        event_hash['start'] = {
            date: DateTime.parse(ev['Start']).strftime("%F")
        }
        event_hash['end'] = {
            date: DateTime.parse(ev['End']).strftime("%F")
        }
      else
        event_hash['start'] = {
            dateTime: DateTime.parse(ev['Start']).strftime("%FT%T%:z")
        }
        event_hash['end'] = {
            dateTime: DateTime.parse(ev['End']).strftime("%FT%T%:z")
        }
      end
      event_hash
      #event_hash.select{|k, v| v}
    end

  end
end