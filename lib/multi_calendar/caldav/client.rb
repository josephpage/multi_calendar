require "net/https"
require "nokogiri"

module Caldav
  class Client
    attr_accessor :caldav_server, :port, :email, :password,
      :debug, :development

    def initialize(email, password, caldav_server, development=false)
      @email = email
      @password = password
      @caldav_server = caldav_server.split("/").first
      @prefix_url =  (caldav_server.split("/",2).try(:[],1) || "")
      @port = 443

      #@caldav_server = "localhost"
      #@port = 1080

      @development = development

      @debug = false
      @_http_cons = {}
    end

    def principal
      @principal ||= fetch_principal
    end

    def calendars
      @calendars ||= fetch_calendars
    end

    def get(url="/", headers = {})
      http_fetch(Net::HTTP::Get, @caldav_server, @prefix_url+url, headers)
    end

    def propfind( url="/", headers = {}, xml)
      http_fetch(Net::HTTP::Propfind, @caldav_server, @prefix_url+url, headers, xml)
    end

    def report( url="/", headers = {}, xml)
      http_fetch(Net::HTTP::Report, @caldav_server, @prefix_url+url, headers, xml)
    end

    def report_without_xml_parsing(url="/", headers = {}, xml)
      http_fetch(Net::HTTP::Report, @caldav_server, @prefix_url+url, headers, xml, false)
    end

    def put( url="/", headers = {}, xml)
      http_fetch(Net::HTTP::Put,@caldav_server, @prefix_url+url, headers, xml)
    end

    def delete( url="/", headers = {}, xml)
      http_fetch(Net::HTTP::Delete,@caldav_server, @prefix_url+url, headers, xml)
    end

    def fetch_calendar_data(url, start_date=nil, end_date=nil)

      filter_xml = '<c:comp-filter name="VEVENT" />'

      if start_date && end_date
        filter_xml = <<END
        <c:comp-filter name="VEVENT">
            <c:time-range start="#{start_date.to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}"
        end="#{end_date.to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}"/>
        </c:comp-filter>
END
      end
      xml_request = <<END
      <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <d:getetag />
          <c:calendar-data >
            <c:comp name="VCALENDAR">
             <c:prop name="VERSION"/>
             <c:comp name="VEVENT">
               <c:prop name="SUMMARY"/>
               <c:prop name="UID"/>
               <c:prop name="DTSTART"/>
               <c:prop name="DTEND"/>
               <c:prop name="DURATION"/>
               <c:prop name="RRULE"/>
               <c:prop name="RDATE"/>
               <c:prop name="EXRULE"/>
               <c:prop name="EXDATE"/>
               <c:prop name="RECURRENCE-ID"/>
             </c:comp>
             <c:comp name="VTIMEZONE"/>
           </c:comp>
          </c:calendar-data>
        </d:prop>
        <c:filter>
          <c:comp-filter name="VCALENDAR">

              #{filter_xml}

          </c:comp-filter>
        </c:filter>
      </c:calendar-query>
END


      xml = self.report(url, { "Depth" => 1 }, xml_request)
      xml.xpath("//cal:calendar-data").map do |calendar_data|
        calendar_data.to_s
      end.compact.join
    end

  private
    def http_fetch(req_type, hhost, url, headers = {}, data = nil, xml_process=true)
      if !(host = @_http_cons["#{hhost}:#{self.port}"])
        host = Net::HTTP.new(hhost, self.port)
        if self.debug
          host.set_debug_output $stdout
        end

        host.use_ssl = true

        if development
          host.verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          host.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        host.start

        @_http_cons["#{hhost}:#{self.port}"] = host
      end

      req = req_type.new(url)
      req.basic_auth self.email, self.password

      req["Connection"] = "keep-alive"
      req["Content-Type"] = "text/xml; charset=\"UTF-8\""


      headers.each do |k,v|
        req[k] = v
      end

      if data
        req.body = data
      end

      res = host.request(req)

      if req_type == Net::HTTP::Put || req_type == Net::HTTP::Delete
        res.code
      else
        Nokogiri::XML(res.body)
      end
    end

    def fetch_principal
      request = <<END
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:current-user-principal/>
  </d:prop>
</d:propfind>
END
      xml = self.propfind( "/", { "Depth" => 1 }, request)
      #modification with http://www.nokogiri.org/tutorials/searching_a_xml_html_document.html  and http://sabre.io/dav/building-a-caldav-client/
      xml.xpath("//d:current-user-principal //d:href /text()").first.text    #check why I need first

    end

    # returns an array of Calendar objects
    def fetch_calendars
      # this is supposed to propfind "calendar-home-set" but icloud doesn't
      # seem to support that, so we skip that lookup and hard-code to
      # "/[principal user id]/calendars/" which is what calendar-home-set would
      # probably return anyway
      request = <<END
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
     <c:calendar-home-set />
  </d:prop>
</d:propfind>
END
      responses = self.propfind( principal, { "Depth" => 1 }, request)
      home_sets = responses.xpath("//cal:calendar-home-set //d:href /text()").map(&:text)

      request = <<END
      <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop>
      <d:resourcetype />
     <d:displayname />
                      <cs:getctag />
     <c:supported-calendar-component-set />
                                  </d:prop>
</d:propfind>
END
      calendars_array = []
      home_sets.each  do |hs|
        responses = self.propfind( hs, { "Depth" => 1 }, request)
        responses.xpath("//cal:supported-calendar-component-set //cal:comp[@name='VEVENT']").each do |c|
          r = c.xpath('./ancestor::d:response[1]')
          name = r.xpath(".//d:displayname /text()").text
          p name
          path = r.xpath(".//d:href /text()").text
          p path
          calendars_array << Caldav::Calendar.new(self, path, name)
        end
      end

      calendars_array


    #   responses.css("D|multistatus D|response").map do |response|
    #     if response
    #       path = response.css("D|href").first.try(:text)
    #       if path =~/\.EML\z/
    #         nil
    #       else
    #         Caldav::Calendar.new(self, path, path.split("/").last)
    #       end
    #     else
    #       nil
    #     end
    #   end.compact
     end


  end
end
