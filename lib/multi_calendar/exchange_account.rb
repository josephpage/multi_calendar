require "viewpoint"

module MultiCalendar
  class ExchangeAccount

    include ActionView::Helpers::TextHelper
    include ERB::Util
    include Viewpoint::EWS

    attr_reader :username, :password, :ews_url, :client, :server_version, :debug, :ssl_version

    def initialize params
      #params[:ews_url] ||= "https://outlook.office365.com/EWS/Exchange.asmx"
      raise "Missing argument username" unless params[:username]
      raise "Missing argument password" unless params[:password]
      raise "Missing argument ews_url" unless params[:ews_url]
      @username = params[:username]
      @password = params[:password]
      @ews_url = params[:ews_url]

      @server_version = params[:server_version]
      @ssl_version = params[:ssl_version]
      @debug = params[:debug]
    end

    def list_calendars
      all_folders = client.folders root: :root, traversal: :deep
      calendar_folders = all_folders.select do |f|
        f.class == Viewpoint::EWS::Types::CalendarFolder
      end

      color_id = 0
      result = []

      calendar_folders.each do |calendar_folder|
        color_id += 1

        result << {
            id: calendar_folder.id,
            summary: calendar_folder.name,
            colorId: color_id
        }
      end

      result
    end

    def list_events params
      items = []

      params[:calendar_ids].each do |calendar_id|

        calendar_folder = client.get_folder(calendar_id)
        client.find_items({
                              :parent_folder_ids=>[
                                  {
                                      :id=>calendar_folder.id,
                                      :change_key=>calendar_folder.change_key
                                  }
                              ],
                              :traversal=>"Shallow",
                              :item_shape=>{:base_shape=>"AllProperties"},
                              :calendar_view=>{
                                  :max_entries_returned=>2000,
                                  :start_date=>params[:start_date],
                                  :end_date=>params[:end_date]
                              }
                          }).each do |calendar_item|
          items << build_event_hash_from_response(calendar_item, calendar_id, false)
        end
      end

      items
    end

    def get_event params
      begin
        calendar_item = client.get_item params[:event_id]
        build_event_hash_from_response(calendar_item, params[:calendar_id])
      rescue
          raise MultiCalendar::EventNotFoundException
      end
    end

    def create_event params
      Viewpoint::EWS::Connection.set_proxy_url ENV['PROXIMO_URL']

      calendar_folder = client.get_folder(params[:calendar_id])
      req = format_event_data(params, "create")
      p req
      calendar_item = calendar_folder.create_item(req, {
          :send_meeting_invitations => "SendToAllAndSaveCopy"
      })

      Viewpoint::EWS::Connection.reset_proxy_url

      {
          event_id: calendar_item.id,
          calendar_id: params[:calendar_id],
          event_url: ""
      }
    end

    def update_event params
      Viewpoint::EWS::Connection.set_proxy_url ENV['PROXIMO_URL']
      calendar_item = client.get_item(params[:event_id])
      new_attributes = format_event_data(params, "update")

      calendar_item.update_item!(new_attributes, {
                                       send_meeting_invitations_or_cancellations: "SendToAllAndSaveCopy"
                                 })
      Viewpoint::EWS::Connection.reset_proxy_url
      true
    end

    def delete_event params
      calendar_item = client.get_item(params[:event_id])
      calendar_item.delete!(:hard, {
          send_meeting_cancellations: "SendOnlyToAll"
      })

      true
    end

    private

    def format_text_as_html text
      h(simple_format(text))
    end

    def format_event_data params, mode="create"
      start_date = params[:start_date].to_time.utc
      end_date = params[:end_date].to_time.utc
      if params[:all_day]
        utc_offset = 0
        if params[:utc_offset]
          utc_offset = params[:utc_offset].to_i
        end
        if utc_offset > 0
          start_date = DateTime.parse(params[:start_date].strftime("%F"))
          end_date = DateTime.parse(params[:end_date].strftime("%F")) - 1
        elsif utc_offset < 0
          start_date = DateTime.parse(params[:start_date].strftime("%F")) + 1
          end_date = DateTime.parse(params[:end_date].strftime("%F"))
        else
          start_date = DateTime.parse(params[:start_date].strftime("%F"))
          end_date = DateTime.parse(params[:end_date].strftime("%F"))
        end

        end_date -= 1
      end
      result = {
          :subject => params[:summary],
          :body => params[:description],
          :start => start_date,
          :end => end_date,
          :is_all_day_event => (params[:all_day])?"true":"false",
          :location => params[:location]
      }
      attendees = params[:attendees] || []
      #unless attendees.map{|att| att[:email]}.include? self.username
      #  attendees << {
      #      email: self.username
      #  }
      #end

      result[:required_attendees] = attendees.map { |att|
        {
            attendee: {
                mailbox: {
                    email_address: att[:email]
                }
            }
        }
      }
      result
    end

    def build_event_hash_from_response calendar_item, calendar_id, full=true
      if full
        organizer_email = (calendar_item.organizer)?(calendar_item.organizer.email):nil
        attendees = (calendar_item.required_attendees.map(&:email) + [organizer_email]).compact.uniq.map{|email|
          {
                displayName: "",
                email: "#{email}"
          }
        }
      else
        attendees = []
      end


      notes = nil
      if full
        begin
          if calendar_item.body_type == "html" || calendar_item.body_type == "HTML"
            notes = Nokogiri::HTML(calendar_item.body).css("body").text
          end
        rescue

        end
        notes ||= calendar_item.body
      end

      event_hash = {
          'id' => calendar_item.id,
          'summary' => calendar_item.subject,
          'description' => "#{notes}",
          'attendees' => attendees,
          'htmlLink' => calendar_item.id,
          'calId' => calendar_id,
          'private' => false,
          'owned' => true,
          'location' => (full)?(calendar_item.location):nil
      }


      if calendar_item.all_day?
        event_hash['start'] = {
            date: calendar_item.start.strftime("%F")
        }
        event_hash['end'] = {
            date: (calendar_item.end + 1).strftime("%F")
        }
        event_hash['all_day'] = true
      else
        event_hash['start'] = {
            dateTime: calendar_item.start.strftime("%FT%T%:z")
        }
        event_hash['end'] = {
            dateTime: calendar_item.end.strftime("%FT%T%:z")
        }
        event_hash['all_day'] = false
      end

      unless full
        event_hash['preview'] = true
      end


      event_hash
    end

    def client
      opts = {}
      if self.server_version
        opts[:server_version] = self.server_version
      end
      opts[:http_opts] = {}
      if self.debug
        opts[:http_opts][:ssl_verify_mode] = 0
      end
      if self.ssl_version
        opts[:http_opts][:ssl_version] = self.ssl_version
      end
      @client ||= Viewpoint::EWSClient.new(self.ews_url, self.username, self.password, opts)
    end
  end
end