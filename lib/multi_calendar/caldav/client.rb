require "net/https"
require "rexml/document"

module Caldav
  class Client
    attr_accessor :caldav_server, :port, :email, :password,
      :debug

    def initialize(email, password, caldav_server)
      @email = email
      @password = password
      @caldav_server = caldav_server
      @port = 443

      @debug = false
      @_http_cons = {}
    end

    def principal
      @principal ||= fetch_principal
    end

    def calendars
      @calendars ||= fetch_calendars
    end

    def get(host, url, headers = {})
      http_fetch(Net::HTTP::Get, host, url, headers)
    end

    def propfind(host, url, headers = {}, xml)
      http_fetch(Net::HTTP::Propfind, host, url, headers, xml)
    end

    def report(host, url, headers = {}, xml)
      http_fetch(Net::HTTP::Report, host, url, headers, xml)
    end

    def report_without_xml_parsing(host, url, headers = {}, xml)
      http_fetch(Net::HTTP::Report, host, url, headers, xml, false)
    end

    def put(host, url, headers = {}, xml)
      http_fetch(Net::HTTP::Put, host, url, headers, xml)
    end

    def delete(host, url, headers = {}, xml)
      http_fetch(Net::HTTP::Delete, host, url, headers, xml)
    end

    def fetch_calendar_data(url, start_date=nil, end_date=nil)

      xml_request = <<END
        <d:sync-collection xmlns:d="DAV:">
          <d:sync-token/>
          <d:prop>
            <d:getcontenttype/>
          </d:prop>
        </d:sync-collection>
END

      if start_date && end_date
        xml_request = <<END
        <C:calendar-query xmlns:D="DAV:"
                 xmlns:C="urn:ietf:params:xml:ns:caldav">
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
           <C:time-range start="#{start_date.to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}"
                         end="#{end_date.to_time.utc.to_datetime.strftime("%Y%m%dT%H%M%SZ")}"/>
         </C:comp-filter>
       </C:comp-filter>
     </C:filter>
   </C:calendar-query>
END
      end


      xml = self.report(self.caldav_server, url, { "Depth" => 1 }, xml_request)

      # gather the separate .ics urls for each event in this calendar
      hrefs = REXML::XPath.each(xml, "//D:href").map do |resp|
        resp.text
      end.compact

      # bundle them all in one multiget
      xml_request_2 = <<END
        <c:calendar-multiget xmlns:d="DAV:"
        xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <c:calendar-data />
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR" />
          </c:filter>
          #{hrefs.map{|h| '<d:href>' << h << '</d:href>'}.join}
        </c:calendar-multiget>
END
      xml = self.report(self.caldav_server, url, { "Depth" => 1 }, xml_request_2)

      REXML::XPath.each(xml, "//C:calendar-data").map{|e| e.text }.join
    end

  private
    def http_fetch(req_type, hhost, url, headers = {}, data = nil, xml_process=true)
      if !(host = @_http_cons["#{hhost}:#{self.port}"])
        host = Net::HTTP.new(hhost, self.port)
        if self.debug
          host.set_debug_output $stdout
        end

        host.use_ssl = true

        host.verify_mode = OpenSSL::SSL::VERIFY_NONE # For development
        #host.verify_mode = OpenSSL::SSL::VERIFY_PEER

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
        REXML::Document.new(res.body)
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
      xml = self.propfind(self.caldav_server, "/", { "Depth" => 1 }, request)

      REXML::XPath.first(xml, "//D:current-user-principal/D:href").text
    end

    # returns an array of Calendar objects
    def fetch_calendars
      # this is supposed to propfind "calendar-home-set" but icloud doesn't
      # seem to support that, so we skip that lookup and hard-code to
      # "/[principal user id]/calendars/" which is what calendar-home-set would
      # probably return anyway

      calendars_url = "#{self.principal.gsub("principals/", "")}/calendar"
      request = <<END
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
  </d:prop>
</d:propfind>
END
      xml = self.propfind(self.caldav_server, calendars_url, { "Depth" => 1 }, request)

      cals = REXML::XPath.each(xml, "//D:multistatus/D:response").map do |cal|
        if cal
          path = cal.elements["D:href"].text
          if path =~/\.EML\z/
            nil
          else
            Caldav::Calendar.new(self, path, path.split("/").last)
          end
        else
          nil
        end
      end.compact
    end


  end
end
