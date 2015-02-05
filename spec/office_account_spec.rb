require 'spec_helper'

describe "OfficeAccount" do

  describe "#new" do
    it "should initialize correctly when everything given" do
      office_account = MultiCalendar::OfficeAccount.new(
          client_id: "CLIENTID",
          client_secret: "CLIENTSECRET",
          refresh_token: "REFRESHTOKEN"
      )
      expect(office_account.client_id).to eq("CLIENTID")
      expect(office_account.client_secret).to eq("CLIENTSECRET")
      expect(office_account.refresh_token).to eq("REFRESHTOKEN")
    end

    it "should raise error when client_id not given" do
      expect {
        MultiCalendar::OfficeAccount.new(
            client_secret: "CLIENTSECRET",
            refresh_token: "REFRESHTOKEN"
        )
      }.to raise_error("Missing argument client_id")
    end

    it "should raise error when client_secret not given" do
      expect {
        MultiCalendar::OfficeAccount.new(
            client_id: "CLIENTID",
            refresh_token: "REFRESHTOKEN"
        )
      }.to raise_error("Missing argument client_secret")
    end

    it "should raise error when refresh_token not given" do
      expect {
        MultiCalendar::OfficeAccount.new(
            client_id: "CLIENTID",
            client_secret: "CLIENTSECRET"
        )
      }.to raise_error("Missing argument refresh_token")
    end
  end

  describe "instance" do
    before(:each) do
      @office_account = MultiCalendar::OfficeAccount.new(
          client_id: "CLIENTID",
          client_secret: "CLIENTSECRET",
          refresh_token: "REFRESHTOKEN"
      )

      stub_request(:post, "https://login.windows.net/common/oauth2/token").
          with(:body => {"client_id"=>"CLIENTID", "client_secret"=>"CLIENTSECRET", "grant_type"=>"refresh_token", "refresh_token"=>"REFRESHTOKEN", "resource"=>"https://outlook.office365.com"},
               :headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Content-Type'=>'application/x-www-form-urlencoded', 'User-Agent'=>'Ruby'}).
          to_return(:status => 200, :body => "{\"access_token\":\"refreshed_access_token\"}", :headers => {})
    end
    describe "#access_token" do
      context "@access_token set" do
        before(:each) do
          @office_account.instance_variable_set(:@access_token, "access_token")
        end
        it "should return @access_token" do
          expect(@office_account.access_token).to eq("access_token")
        end
      end

      context "@access_token not set" do
        before(:each) do
          allow(@office_account).to receive(:refresh_access_token).and_return("refreshed_access_token")
        end
        it "should call refresh_token" do
          expect(@office_account).to receive(:refresh_access_token).and_return("refreshed_access_token")
          @office_account.access_token
        end
        it "set @access_token" do
          @office_account.access_token
          expect(@office_account.instance_variable_get(:@access_token)).to eq("refreshed_access_token")
        end
        it "return access_token" do
          expect(@office_account.access_token).to eq("refreshed_access_token")
        end
      end
    end

    describe "#refresh_access_token" do
      it "should return access_token" do
        expect(@office_account.refresh_access_token).to eq('refreshed_access_token')
      end
      it "should set @access_token" do
        @office_account.refresh_access_token
        expect(@office_account.instance_variable_get(:@access_token)).to eq('refreshed_access_token')
      end
    end

    describe "#list_calendars" do
      it "should list calendars" do
        stub_request(:get, "https://outlook.office365.com/api/v1.0/me/calendars").
            with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 200, :body => "{\"value\":[{\"Id\":\"cid1\",\"Name\":\"Calendar 1\"},{\"Id\":\"cid2\",\"Name\":\"Calendar 2\"}]}", :headers => {})


        expect(@office_account.list_calendars).to eq([
                                                         {:id=>"cid1", :summary=>"Calendar 1", :colorId=>1},
                                                         {:id=>"cid2", :summary=>"Calendar 2", :colorId=>2}
                                                     ])
      end
    end

    describe "#list_events" do
      it "should list events" do
        stub_request(:get, "https://outlook.office365.com/api/v1.0/me/calendars/cid1/calendarview?$skip=0&$top=50&endDateTime=2015-01-30T00:00:00Z&startDateTime=2015-01-01T00:00:00Z").
            with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 200, :body => "{\"value\":[{\"Id\":\"eid1\",\"Subject\":\"Cool event #1\",\"Location\":{\"DisplayName\":\"Cool place #1\"},\"BodyPreview\":\"Cool notes #1\",\"Attendees\":[{\"EmailAddress\":{\"Name\":\"Mark Zuck\",\"Address\":\"mark@zuck.com\"},\"StatusResponse\":\"Attending\"},{\"EmailAddress\":{\"Name\":\"John Doe\",\"Address\":\"john@doe.com\"},\"StatusResponse\":\"Declined\"}],\"IsAllDay\":\"1\",\"Start\":\"2015-01-02\",\"End\":\"2015-01-03\"},{\"Id\":\"eid2\",\"Subject\":\"Cool event #2\",\"Attendees\":[],\"Start\":\"2015-01-02T12:00\",\"End\":\"2015-01-02T13:00\"}]}", :headers => {})

        stub_request(:get, "https://outlook.office365.com/api/v1.0/me/calendars/cid2/calendarview?$skip=0&$top=50&endDateTime=2015-01-30T00:00:00Z&startDateTime=2015-01-01T00:00:00Z").
            with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 200, :body => "{\"value\":[]}", :headers => {})

        expect(@office_account.list_events(
            start_date: DateTime.new(2015, 1, 1),
            end_date: DateTime.new(2015, 1, 30),
            calendar_ids: ["cid1", "cid2"]
               )).to eq([
                            {"id"=>"eid1", "summary"=>"Cool event #1", "description"=>"Cool notes #1", "attendees"=>[{:displayName=>"Mark Zuck", :email=>"mark@zuck.com"}, {:displayName=>"John Doe", :email=>"john@doe.com"}], "htmlLink"=>"eid1", "calId"=>"cid1","location"=>"Cool place #1", "start"=>{:date=>"2015-01-02"}, "end"=>{:date=>"2015-01-03"}},
                            {"id"=>"eid2", "summary"=>"Cool event #2", "description"=>"", "attendees"=>[], "htmlLink"=>"eid2", "calId"=>"cid1", "start"=>{:dateTime=>"2015-01-02T12:00:00+00:00"}, "end"=>{:dateTime=>"2015-01-02T13:00:00+00:00"}}
                        ])
      end
    end

    describe "#get_event" do
      it "should get an event" do
        stub_request(:get, "https://outlook.office365.com/api/v1.0/me/events/eid1").
            with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 200, :body => "{\"Id\":\"eid1\",\"Subject\":\"Cool event #1\",\"Location\":{\"DisplayName\":\"Cool place #1\"},\"BodyPreview\":\"Cool notes #1\",\"Attendees\":[{\"EmailAddress\":{\"Name\":\"Mark Zuck\",\"Address\":\"mark@zuck.com\"},\"StatusResponse\":\"Attending\"},{\"EmailAddress\":{\"Name\":\"John Doe\",\"Address\":\"john@doe.com\"},\"StatusResponse\":\"Declined\"}],\"IsAllDay\":\"1\",\"Start\":\"2015-01-02\",\"End\":\"2015-01-03\"}", :headers => {})

        expect(@office_account.get_event(
                   calendar_id: "cid1",
                   event_id: "eid1"
               )).to eq({"id"=>"eid1", "summary"=>"Cool event #1", "description"=>"Cool notes #1", "attendees"=>[{:displayName=>"Mark Zuck", :email=>"mark@zuck.com"}, {:displayName=>"John Doe", :email=>"john@doe.com"}], "htmlLink"=>"eid1","location"=>"Cool place #1", "start"=>{:date=>"2015-01-02"}, "end"=>{:date=>"2015-01-03"}})
      end
    end

    describe "#create_event" do
      it "should create event" do
        stub_request(:post, "https://outlook.office365.com/api/v1.0/me/calendars/cid1/events").
            with(:body => "{\"Subject\":\"New event\",\"Body\":{\"ContentType\":\"HTML\",\"Content\":\"<p>created by Multi-Calendar gem</p>\"},\"Start\":\"2015-01-01T12:00:00+00:00\",\"End\":\"2015-01-01T13:00:00+00:00\",\"Location\":{\"DisplayName\":\"Paris\"},\"Attendees\":[{\"EmailAddress\":{\"Address\":\"you@yourdomain.com\"},\"Type\":\"Required\"}]}",
                 :headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 201, :body => "{\"Id\":\"eid1\"}", :headers => {})


        expect(@office_account.create_event(
            calendar_id: "cid1",
            start_date: DateTime.new(2015,1,1,12,0),
            end_date: DateTime.new(2015,1,1,13,0),
            summary: "New event",
            description: "created by Multi-Calendar gem",
            attendees: [{email: "you@yourdomain.com"}],
            location: "Paris"
        )).to eq("eid1")
      end
    end

    describe "#update_event" do
      it "should update event" do
        stub_request(:patch, "https://outlook.office365.com/api/v1.0/me/events/eid1").
            with(:body => "{\"Subject\":\"New event\",\"Body\":{\"ContentType\":\"HTML\",\"Content\":\"<p>created by Multi-Calendar gem</p>\"},\"Start\":\"2015-01-01T12:00:00+00:00\",\"End\":\"2015-01-01T13:00:00+00:00\",\"Location\":{\"DisplayName\":\"Paris\"},\"Attendees\":[{\"EmailAddress\":{\"Address\":\"you@yourdomain.com\"},\"Type\":\"Required\"}]}",
                 :headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 200, :body => "", :headers => {})

        expect(@office_account.update_event(
                   calendar_id: "cid1",
                   event_id: "eid1",
                   start_date: DateTime.new(2015,1,1,12,0),
                   end_date: DateTime.new(2015,1,1,13,0),
                   summary: "New event",
                   description: "created by Multi-Calendar gem",
                   attendees: [{email: "you@yourdomain.com"}],
                   location: "Paris"
               )).to eq(true)
      end
    end

    describe "#delete_event" do
      it "should delete event" do
        stub_request(:delete, "https://outlook.office365.com/api/v1.0/me/events/eid1").
            with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'Bearer refreshed_access_token', 'Content-Type'=>'application/json', 'User-Agent'=>'Ruby'}).
            to_return(:status => 204, :body => "", :headers => {})

        expect(@office_account.delete_event(
                   calendar_id: "cid1",
                   event_id: "eid1"
               )).to eq(true)
      end
    end
  end
end