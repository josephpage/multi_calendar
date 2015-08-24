require "spec_helper"

describe MultiCalendar::ActivesyncAccount do
	describe "constructor" do
		context "No arg" do
			it "should raise" do
				expect{MultiCalendar::ActivesyncAccount.new()}.to raise_error "Missing argument username"
			end
		end
		context "Missing password" do
			it "should raise" do
				expect{MultiCalendar::ActivesyncAccount.new({
					username: "username"
					})}.to raise_error "Missing argument password"
			end
		end

		context "Missing device_id" do
			it "should raise" do
				expect{MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password"
					})}.to raise_error "Missing argument device_id"
			end
		end

		context "Missing device_type" do
			it "should raise" do
				expect{MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password",
					device_id: "device_id"
					})}.to raise_error "Missing argument device_type"
			end
		end

		context "Missing server_url" do
			it "should raise" do
				expect{MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type"
					})}.to raise_error "Missing argument server_url"
			end
		end

		context "All arguments set" do
			it "should create correctly" do
				expect(ActiveSync::Client).to receive(:new).with({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type",
					server_url: "https://www.server.com",
					policy_key: nil
					})

				MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type",
					server_url: "https://www.server.com"
					})
			end

			it "should create correctmy with policy_key" do
				expect(ActiveSync::Client).to receive(:new).with({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type",
					server_url: "https://www.server.com",
					policy_key: "1234"
					})

				MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type",
					server_url: "https://www.server.com",
					policy_key: "1234"
					})
			end
		end
	end

	describe "Instance" do
		before do
			@account = MultiCalendar::ActivesyncAccount.new({
					username: "username",
					password: "password",
					device_id: "device_id",
					device_type: "device_type",
					server_url: "https://www.server.com",
					})
		end
	

		describe "list_calendars" do
			it "it should list calendars" do
				expect(@account.client).to receive(:folder_sync_request).with(sync_key: 0).and_return(Nokogiri::XML(<<END
<?xml version="1.3" encoding="UTF-8"?>
<folderhierarchy:FolderSync xmlns:folderhierarchy="FolderHierarchy">
  <folderhierarchy:Status>1</folderhierarchy:Status>
  <folderhierarchy:SyncKey>1</folderhierarchy:SyncKey>
  <folderhierarchy:Changes>
    <folderhierarchy:Count>5</folderhierarchy:Count>
    
    <folderhierarchy:Add>
      <folderhierarchy:ServerId>3</folderhierarchy:ServerId>
      <folderhierarchy:ParentId>0</folderhierarchy:ParentId>
      <folderhierarchy:DisplayName>Drafts</folderhierarchy:DisplayName>
      <folderhierarchy:Type>3</folderhierarchy:Type>
    </folderhierarchy:Add>
    <folderhierarchy:Add>
      <folderhierarchy:ServerId>4</folderhierarchy:ServerId>
      <folderhierarchy:ParentId>0</folderhierarchy:ParentId>
      <folderhierarchy:DisplayName>MainCal</folderhierarchy:DisplayName>
      <folderhierarchy:Type>8</folderhierarchy:Type>
    </folderhierarchy:Add>
    <folderhierarchy:Add>
      <folderhierarchy:ServerId>5</folderhierarchy:ServerId>
      <folderhierarchy:ParentId>4</folderhierarchy:ParentId>
      <folderhierarchy:DisplayName>Cal2</folderhierarchy:DisplayName>
      <folderhierarchy:Type>13</folderhierarchy:Type>
    </folderhierarchy:Add>
    <folderhierarchy:Add>
      <folderhierarchy:ServerId>6</folderhierarchy:ServerId>
      <folderhierarchy:ParentId>4</folderhierarchy:ParentId>
      <folderhierarchy:DisplayName>Cal3</folderhierarchy:DisplayName>
      <folderhierarchy:Type>13</folderhierarchy:Type>
    </folderhierarchy:Add>
    <folderhierarchy:Add>
      <folderhierarchy:ServerId>7</folderhierarchy:ServerId>
      <folderhierarchy:ParentId>0</folderhierarchy:ParentId>
      <folderhierarchy:DisplayName>Contacts</folderhierarchy:DisplayName>
      <folderhierarchy:Type>9</folderhierarchy:Type>
    </folderhierarchy:Add>
  </folderhierarchy:Changes>
</folderhierarchy:FolderSync>
END
))

				expect(@account.list_calendars).to eq([
					{
						:id=>"4",
						:summary=>"MainCal",
						:main=>true,
						:colorId=>1
					},
					{
						:id=>"5",
						:summary=>"Cal2",
						:main=>false,
						:colorId=>2
					},
					{
						:id=>"6",
						:summary=>"Cal3",
						:main=>false,
						:colorId=>3
					}
				])
			end
		end

		describe "list_events" do
			context "No calendar_id given" do
				it "it should raise" do
					expect{@account.list_events}.to raise_error("Missing param calendar_id")
				end
			end

			context "calendar_id given" do
				it "it should returns events" do
					expect(@account.client).to receive(:sync_request).with({sync_key: "0", collection_id: "13"}).and_return(Nokogiri::XML(<<END
<?xml version="1.3" encoding="UTF-8"?>
<airsync:Sync xmlns:folderhierarchy="AirSync">
	<Collections>
    	<Collection>
      		<SyncKey>1450798397</SyncKey>
      		<CollectionId>4</CollectionId>
      		<Status>1</Status>
    	</Collection>
  	</Collections>
</airsync:Sync>
END
))

					expect(@account.client).to receive(:sync_request).with({sync_key: "1450798397", collection_id: "13"}).and_return(Nokogiri::XML(<<END
<?xml version="1.3" encoding="UTF-8"?>
<airsync:Sync xmlns:folderhierarchy="AirSync">
	<Collections>
    	<Collection>
      		<SyncKey>1450798398</SyncKey>
      		<CollectionId>4</CollectionId>
      		<Status>1</Status>
      		<MoreAvailable></MoreAvailable>
      		<Commands>
		        <Add>
		          <ServerId>4:101</ServerId>
		          <ApplicationData>
		            <calendar:Timezone xmlns:calendar="Calendar">AAAAAEcAcgBlAGUAbgB3AGkAYwBoACAAUwB0AGEAbgBkAGEAcgBkACAAVABpAG0AZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgAVQBUAEMAKQAgAE0AbwBuAHIAbwB2AGkAYQAsACAAUgBlAHkAawBqAGEAdgBpAGsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==</calendar:Timezone>
		            <calendar:DtStamp xmlns:calendar="Calendar">20150821T134530Z</calendar:DtStamp>
		            <calendar:StartTime xmlns:calendar="Calendar">20150703T080000Z</calendar:StartTime>
		            <calendar:Subject xmlns:calendar="Calendar">TOUR rubensteinpublishing.com</calendar:Subject>
		            <calendar:UID xmlns:calendar="Calendar">SHYXI2ReWTaDIFs9QW8AUg@juliedesk.com</calendar:UID>
		            <calendar:OrganizerName xmlns:calendar="Calendar">julie@juliedesk.com</calendar:OrganizerName>
		            <calendar:OrganizerEmail xmlns:calendar="Calendar">julie@juliedesk.com</calendar:OrganizerEmail>
		            <calendar:Attendees xmlns:calendar="Calendar">
		              <calendar:Attendee>
		                <calendar:Email>nicolas@marlier.onmicrosoft.com</calendar:Email>
		                <calendar:Name>Nicolas Marlier</calendar:Name>
		                <calendar:AttendeeType>1</calendar:AttendeeType>
		              </calendar:Attendee>
		            </calendar:Attendees>
		            <calendar:Location xmlns:calendar="Calendar">London, London Bridge - Hays Lane</calendar:Location>
		            <calendar:EndTime xmlns:calendar="Calendar">20150703T090000Z</calendar:EndTime>
		            <airsyncbase:Body xmlns:airsyncbase="AirSyncBase">
		              <airsyncbase:Type>1</airsyncbase:Type>
		              <airsyncbase:EstimatedDataSize>147</airsyncbase:EstimatedDataSize>
		              <airsyncbase:Truncated>1</airsyncbase:Truncated>
		            </airsyncbase:Body>
		            <calendar:Categories xmlns:calendar="Calendar">
		              <calendar:Category>Catégorie Rouge</calendar:Category>
		              <calendar:Category>Red Category</calendar:Category>
		            </calendar:Categories>
		            <calendar:Sensitivity xmlns:calendar="Calendar">0</calendar:Sensitivity>
		            <calendar:BusyStatus xmlns:calendar="Calendar">1</calendar:BusyStatus>
		            <calendar:AllDayEvent xmlns:calendar="Calendar">0</calendar:AllDayEvent>
		            <calendar:Reminder xmlns:calendar="Calendar">

		            </calendar:Reminder>
		            <calendar:MeetingStatus xmlns:calendar="Calendar">3</calendar:MeetingStatus>
		            <airsyncbase:NativeBodyType xmlns:airsyncbase="AirSyncBase">1</airsyncbase:NativeBodyType>
		            <calendar:ResponseRequested xmlns:calendar="Calendar">1</calendar:ResponseRequested>
		            <calendar:ResponseType xmlns:calendar="Calendar">5</calendar:ResponseType>
		          </ApplicationData>
		        </Add>
		    </Commands>
    	</Collection>
  	</Collections>
</airsync:Sync>
END
))

expect(@account.client).to receive(:sync_request).with({sync_key: "1450798398", collection_id: "13"}).and_return(Nokogiri::XML(<<END
<?xml version="1.3" encoding="UTF-8"?>
<airsync:Sync xmlns:folderhierarchy="AirSync">
	<Collections>
    	<Collection>
      		<SyncKey>1450798399</SyncKey>
      		<CollectionId>4</CollectionId>
      		<Status>1</Status>
      		<Commands>
		        <Add>
		          <ServerId>4:102</ServerId>
		          <ApplicationData>
		            <calendar:Timezone xmlns:calendar="Calendar">AAAAAEcAcgBlAGUAbgB3AGkAYwBoACAAUwB0AGEAbgBkAGEAcgBkACAAVABpAG0AZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgAVQBUAEMAKQAgAE0AbwBuAHIAbwB2AGkAYQAsACAAUgBlAHkAawBqAGEAdgBpAGsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==</calendar:Timezone>
		            <calendar:Subject xmlns:calendar="Calendar">TOUR - 2</calendar:Subject>
		            <calendar:UID xmlns:calendar="Calendar">SHYXI2ReWTaDIFs9QW8AUg@juliedesk.com</calendar:UID>
		            <calendar:Location xmlns:calendar="Calendar">London, London Bridge - Hays Lane</calendar:Location>
		            <calendar:EndTime xmlns:calendar="Calendar">20150703T090000Z</calendar:EndTime>
		            <calendar:StartTime xmlns:calendar="Calendar">20150703T080000Z</calendar:EndTime>
		          </ApplicationData>
		        </Add>
		    </Commands>
    	</Collection>
  	</Collections>
</airsync:Sync>
END
))
					
					expect(@account.list_events({calendar_id: "13"})).to eq([
							{
								'id'=>"4:101",
								'uid' => "SHYXI2ReWTaDIFs9QW8AUg@juliedesk.com",
								'summary'=>"TOUR rubensteinpublishing.com",
								'description'=>'',
								'location'=>'',
								'start' => {
									'dateTime' => "2015-07-03T08:00:00Z"
								},
								'end' => {
									'dateTime' => "2015-07-03T09:00:00Z"
								},
								'calId' => "13",
								'all_day' => false,
								'attendees' => [],
								'recurringEventId' => nil,
								'recurrence' => []
							},
							{
								'id'=>"4:102",
								'uid' => "SHYXI2ReWTaDIFs9QW8AUg@juliedesk.com",
								'summary'=>"TOUR - 2",
								'description'=>'',
								'location'=>'',
								'start' => {
									'dateTime' => "2015-07-03T08:00:00Z"
								},
								'end' => {
									'dateTime' => "2015-07-03T09:00:00Z"
								},
								'calId' => "13",
								'all_day' => false,
								'attendees' => [],
								'recurringEventId' => nil,
								'recurrence' => []
							}
						])
				end
			end
		end

		describe "create_event" do
			context "No calendar_id" do
				it "it should raise" do
					expect{@account.create_event}.to raise_error("Missing param calendar_id")
				end
			end
			context "No summary" do
				it "it should raise" do
					expect{@account.create_event({
						calendar_id: "13"
						})}.to raise_error("Missing param summary")
				end
			end
			context "No start_date" do
				it "it should raise" do
					expect{@account.create_event({
						calendar_id: "13",
						summary: "New event"
						})}.to raise_error("Missing param start_date")
				end
			end
			context "No end_date" do
				it "it should raise" do
					expect{@account.create_event({
						calendar_id: "13",
						summary: "New event",
						start_date: DateTime.parse("2015-01-01T12:00:00")
						})}.to raise_error("Missing param end_date")
				end
			end

			context "All set" do
				before do
					expect(@account).to receive(:list_events).with(calendar_id: "13") do
						@account.instance_variable_set(:@sync_keys, {"13" => "1234"})
					end

					allow(@account).to receive(:generate_uid).and_return("1234567890ABCDEFGHIJKLMNOPQRST")
					allow(DateTime).to receive(:now).and_return(DateTime.parse("2010-01-01"))
					
					@create_event_request_params = {
							sync_key: "1234",
							collection_id: "13",
							subject: "New event",
							start_time: "20150101T120000Z",
							end_time: "20150101T130000Z",

							:client_id=>1,
							:timezone=>"Atlantic/Reykjavik",
							:all_day_event=>0,
							:busy_status=>2,
							:dt_stamp=>"20100101T000000Z",
							:sensitivity=>0,
							:location=>nil,
							:body=>nil,
							:id=>"1234567890ABCDEFGHIJKLMNOPQRST",
							:meeting_status=>0,
							:attendees=>[]
						}
					@create_event_request_response = Nokogiri::XML(<<END

<?xml version="1.3" encoding="UTF-8"?>
<airsync:Sync xmlns:folderhierarchy="AirSync">
	<Collections>
    	<Collection>
      		<SyncKey>1450798399</SyncKey>
      		<CollectionId>4</CollectionId>
      		<Status>1</Status>
      		
			<Responses>
        		<Add>
          			<ClientId>1</ClientId>
          			<ServerId>4:151</ServerId>
          			<Status>1</Status>
        		</Add>
      		</Responses>
  		</Collection>
	</Collections>
</airsync:Sync>
END
)
				end
			
				context "No attendee" do
					it "it should create event" do
						expect(@account.client).to receive(:create_event_request).with(@create_event_request_params).and_return(@create_event_request_response)
						result = @account.create_event({
							calendar_id: "13",
							summary: "New event",
							start_date: DateTime.parse("2015-01-01T12:00:00"),
							end_date: DateTime.parse("2015-01-01T13:00:00")
						})

						expect(result[:calendar_id]).to eq("13")
						expect(result[:uid]).to eq("1234567890ABCDEFGHIJKLMNOPQRST")
					end
				end

				context "Attendees" do
					it "it should create event and send invites" do
						@create_event_request_params[:attendees] = ["nicolas@juliedesk.com","nicolas2@juliedesk.com"]
						allow(@account).to receive(:generate_client_id).and_return("ZE02BR5A-3SJQ-HT1W-U8LH-4B7D3VFBW89V")
						expect(@account.client).to receive(:create_event_request).with(@create_event_request_params).and_return(@create_event_request_response)
						expect(@account.client).to receive(:send_invitation_request).with({
							:attendees=>["nicolas@juliedesk.com", "nicolas2@juliedesk.com"],
							:subject=>"New event",
							:body=>nil,
							:uid=>"1234567890ABCDEFGHIJKLMNOPQRST",
							:client_id=>"ZE02BR5A-3SJQ-HT1W-U8LH-4B7D3VFBW89V",
							:dt_stamp=>DateTime.parse("2010-01-01"),
							:start_time=>"20150101T120000Z",
							:end_time=>"20150101T130000Z",
							:start_timezone=>"Atlantic/Reykjavik",
							:end_timezone=>"Atlantic/Reykjavik"
							}).and_return(Nokogiri::XML(""))

						result = @account.create_event({
							calendar_id: "13",
							summary: "New event",
							start_date: DateTime.parse("2015-01-01T12:00:00"),
							end_date: DateTime.parse("2015-01-01T13:00:00"),
							attendees: ["nicolas@juliedesk.com","nicolas2@juliedesk.com"]
						})

						expect(result[:calendar_id]).to eq("13")
						expect(result[:uid]).to eq("1234567890ABCDEFGHIJKLMNOPQRST")
					end
				end
			end
		end

		describe "update_event" do
			context "No calendar_id" do
				it "it should raise" do
					expect{@account.update_event}.to raise_error("Missing param calendar_id")
				end
			end
			context "No event_id" do
				it "it should raise" do
					expect{@account.update_event({
						calendar_id: "13"
						})}.to raise_error("Missing param event_id")
				end
			end
			context "No summary" do
				it "it should raise" do
					expect{@account.update_event({
						calendar_id: "13",
						event_id: "0:141",
						})}.to raise_error("Missing param summary")
				end
			end
			context "No start_date" do
				it "it should raise" do
					expect{@account.update_event({
						calendar_id: "13",
						event_id: "0:141",
						summary: "New event"
						})}.to raise_error("Missing param start_date")
				end
			end
			context "No end_date" do
				it "it should raise" do
					expect{@account.update_event({
						calendar_id: "13",
						event_id: "0:141",
						summary: "New event",
						start_date: DateTime.parse("2015-01-01T12:00:00")
						})}.to raise_error("Missing param end_date")
				end
			end

			context "All set" do
				before do
					expect(@account).to receive(:list_events).with(calendar_id: "13").and_return([{
							server_id: "0:141",
							id: "1234567890ABCDEFGHIJKLMNOPQRST"
							}])

					allow(@account).to receive(:get_sync_key).with("13").and_return("1234")

					allow(DateTime).to receive(:now).and_return(DateTime.parse("2010-01-01"))
					
					@update_event_request_params = {
							sync_key: "1234",
							collection_id: "13",
							server_id: "0:141",
							subject: "New event",
							start_time: "20150101T120000Z",
							end_time: "20150101T130000Z",

							:client_id=>1,
							:timezone=>"Atlantic/Reykjavik",
							:all_day_event=>0,
							:busy_status=>2,
							:dt_stamp=>"20100101T000000Z",
							:sensitivity=>0,
							:location=>nil,
							:body=>nil,
							:id=>"1234567890ABCDEFGHIJKLMNOPQRST",
							:meeting_status=>0,
							:attendees=>[]
						}
					@update_event_request_response = Nokogiri::XML(<<END
<?xml version="1.3" encoding="UTF-8"?>
<airsync:Sync xmlns:folderhierarchy="AirSync">
	<Collections>
    	<Collection>
      		<SyncKey>1450798399</SyncKey>
      		<CollectionId>4</CollectionId>
      		<Status>1</Status>
      		
			<Responses>
        		<Add>
          			<ClientId>1</ClientId>
          			<ServerId>4:151</ServerId>
          			<Status>1</Status>
        		</Add>
      		</Responses>
  		</Collection>
	</Collections>
</airsync:Sync>
END
)
				end
			
				context "No attendee" do
					it "it should update event" do
						expect(@account.client).to receive(:update_event_request).with(@update_event_request_params).and_return(@update_event_request_response)
						result = @account.update_event({
							calendar_id: "13",
							event_id: "0:141",
							summary: "New event",
							start_date: DateTime.parse("2015-01-01T12:00:00"),
							end_date: DateTime.parse("2015-01-01T13:00:00")
						})
					end
				end

				context "Attendees" do
					it "it should create event and send invites" do
						@update_event_request_params[:attendees] = ["nicolas@juliedesk.com","nicolas2@juliedesk.com"]
						allow(@account).to receive(:generate_client_id).and_return("ZE02BR5A-3SJQ-HT1W-U8LH-4B7D3VFBW89V")
						expect(@account.client).to receive(:update_event_request).with(@update_event_request_params).and_return(@update_event_request_response)
						expect(@account.client).to receive(:send_invitation_request).with({
							:attendees=>["nicolas@juliedesk.com", "nicolas2@juliedesk.com"],
							:subject=>"New event",
							:body=>nil,
							:uid=>"1234567890ABCDEFGHIJKLMNOPQRST",
							:client_id=>"ZE02BR5A-3SJQ-HT1W-U8LH-4B7D3VFBW89V",
							:dt_stamp=>DateTime.parse("2010-01-01"),
							:start_time=>"20150101T120000Z",
							:end_time=>"20150101T130000Z",
							:start_timezone=>"Atlantic/Reykjavik",
							:end_timezone=>"Atlantic/Reykjavik"
							}).and_return(Nokogiri::XML(""))
						
						result = @account.update_event({
							calendar_id: "13",
							event_id: "0:141",
							summary: "New event",
							start_date: DateTime.parse("2015-01-01T12:00:00"),
							end_date: DateTime.parse("2015-01-01T13:00:00"),
							attendees: ["nicolas@juliedesk.com","nicolas2@juliedesk.com"]
						})
					end
				end
			end
		end

		describe "delete_event" do
			it "it should delete event" do
				expect(@account).to receive(:list_events).with(calendar_id: "1")
				expect(@account.client).to receive(:delete_event_request).with({
					sync_key: "0",
					collection_id: "1",
					server_id: "1234"
				}).and_return(Nokogiri::XML(""))
				@account.delete_event({
					event_id: "1234",
					calendar_id: "1"
				})
			end
		end

		describe "generate_uid" do
			it "should return a well-formed uid" do
				10.times do 
					expect(@account.send(:generate_uid)).to match(/([A-Z0-9]){30}/)
				end
			end
		end

		describe "generate_client_id" do
			it "should return a well-formed client_id" do
				10.times do 
					expect(@account.send(:generate_client_id)).to match(/([A-Z0-9]){8}-([A-Z0-9]){4}-([A-Z0-9]){4}-([A-Z0-9]){4}-([A-Z0-9]){12}/)
				end
			end
		end
	end
	
end