require "net/https"
require "nokogiri"

module Net
  class HTTP
    class Report < HTTPRequest
      METHOD = "REPORT"
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end
  end
end

module Caldav
  class Client
    attr_accessor :caldav_server, :port, :email, :password,
      :debug, :development, :is_icloud

    def initialize(email, password, caldav_server, development=false, is_icloud=false)
      @email = email
      @password = password
      @caldav_server = caldav_server
      @port = 443

      @development = development

      @debug = false
      @_http_cons = {}
      @is_icloud = is_icloud
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

      xml = self.report(self.caldav_server, url, { "Depth" => 1 }, xml_request)

      if is_icloud
        hrefs = xml.css("response").map do |resp|
          resp.css("href").first.text
        end.select(&:present?)
      else
        begin
          hrefs = xml.xpath("//d:response").map do |resp|
            resp.xpath("d:href").first.text
          end.select(&:present?)
        rescue Nokogiri::XML::XPath::SyntaxError
          return []
        end
      end

      xml_request_2  = <<END
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
      xml_2 = self.report(self.caldav_server, url, { "Depth" => 1 }, xml_request_2)

      if is_icloud
        responses = xml_2.css("response")
      else
        begin
          responses = xml_2.xpath("//d:response")
        rescue Nokogiri::XML::XPath::SyntaxError
          return []
        end
      end

      responses.map do |response|
        if is_icloud
          url = response.css("href").text
          event_data = response.css("prop *").text
        else
          url = response.xpath("d:href").text
          event_data = response.xpath("d:propstat/d:prop/*").text
        end

        if url && event_data
          {
              url: url,
              event_data: event_data
          }
        else
          nil
        end
      end.compact
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
        if xml_process
          Nokogiri::XML(res.body)
        else
          res.body
        end
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
      #modification with http://www.nokogiri.org/tutorials/searching_a_xml_html_document.html  and http://sabre.io/dav/building-a-caldav-client/
      if is_icloud
        result = xml.css("current-user-principal href").text
      else
        result = xml.xpath("//d:current-user-principal/d:href").first.text    #check why I need first
      end

      raise "No principal found" unless result.present?
      result
    end


    def fetch_calendars
      request = <<END
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <c:calendar-home-set/>
  </d:prop>
</d:propfind>
END
      responses = self.propfind(self.caldav_server, principal, { "Depth" => 1 }, request)

      if is_icloud
        home_sets = responses.css("prop href").map(&:text)
      else
        home_sets = responses.xpath("//cal:calendar-home-set/d:href").map(&:text)
      end


      request = <<END
<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:resourcetype/>
    <d:displayname/>
    <cs:getctag/>
    <c:supported-calendar-component-set/>
  </d:prop>
</d:propfind>
END
      calendars_array = []
      home_sets.each  do |hs|

        responses = self.propfind(self.caldav_server, hs, { "Depth" => 1 }, request)

        if is_icloud
          responses.css("multistatus response").each do |cal|
            if cal
              path = cal.css("href").first.try(:text)
              begin
                if cal.css("propstat prop displayname").length > 0
                  name = cal.css("propstat prop displayname").first.text
                  if name.present? && path.present?
                    calendars_array << Caldav::Calendar.new(self, path, name)
                  end
                end
              rescue NoMethodError
              end
            end
          end
        else
          responses.xpath("//cal:supported-calendar-component-set //cal:comp[@name='VEVENT']").each do |c|
            r = c.xpath('./ancestor::d:response[1]')
            name = r.xpath(".//d:displayname /text()").text
            path = r.xpath(".//d:href /text()").text
            calendars_array << Caldav::Calendar.new(self, path, name)
          end
        end

      end

      calendars_array.uniq(&:path)
     end


  end
end
