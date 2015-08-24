require "active_sync"

module MultiCalendar
	class ActivesyncAccount
		include ActiveSync

	    attr_accessor :username, :password, :activesync_url, :device_id, :device_type, :client, :server_url, :policy_key

	    # Creates a new account and set the client instance variable
		# username, password, device_id, device_type and server_url are required
		# policy_key is optional. If not set, it will be found when making the first request
		def initialize params={}
			[:username, :password, :device_id, :device_type, :server_url].each do |key|
				raise "Missing argument #{key}" unless params[key]
			end

			self.username 		= params[:username]
			self.password 		= params[:password]
			self.device_id 		= params[:device_id]
			self.device_type	= params[:device_type]
			self.server_url 	= params[:server_url]
			self.policy_key 	= params[:policy_key] 
			
			self.client = ActiveSync::Client.new({
				username: 		self.username,
				password: 		self.password,
				device_id: 		self.device_id,
				device_type: 	self.device_type,
				server_url: 	self.server_url,
				policy_key:     self.policy_key
			})
		end

	    # List the user calendars
		def list_calendars
			response = client.folder_sync_request sync_key: 0
			response.remove_namespaces!
			color_id = 0
			response.css("Add").select do |folder_item|
				["8", "13"].include? folder_item.css("Type").text
			end.map do |folder_item|
				color_id += 1

				{
					id: folder_item.css("ServerId").text,
					summary: folder_item.css("DisplayName").text,
					main: folder_item.css("Type").text == "8",
					colorId: color_id
				}
			end
		end

		# List the user events for a given calendar_id (required arg)
		def list_events params={}
			list_events_full(params)[:new_events]
		end

		def list_events_full params={}
			raise "Missing param calendar_id" unless params[:calendar_id]
			new_events = []
			deleted_events = []
			updated_events = []

			if get_sync_key(params[:calendar_id]) == "0"
				response = make_request(:sync_request, {
					sync_key: get_sync_key(params[:calendar_id]),
					collection_id: params[:calendar_id]
				})
			end

			continue = true
			while continue do
				response = make_request(:sync_request, {
					sync_key: get_sync_key(params[:calendar_id]),
					collection_id: params[:calendar_id]
				})
				response.remove_namespaces!
				response.css("Add").each do |event_item|
					new_events << parse_event(event_item, params[:calendar_id])
				end
				response.css("Change").each do |event_item|
					updated_events << parse_event(event_item, params[:calendar_id])
				end
				response.css("Delete").each do |event_item|
					deleted_events << parse_deleted_event(event_item)
				end
				continue = response.css("MoreAvailable").length > 0
			end
			{
				new_events: new_events,
				updated_events: updated_events,
				deleted_events: deleted_events
			}
		end


		# Creates an event in the user calendar identified by calendar_id
		# This also send invites if attendees arg is a non-empty array
		# Returns event_id, calendar_id and uid
		def create_event params={}
			[:calendar_id, :summary, :start_date, :end_date].each do |key|
				raise "Missing param #{key}" unless params[key]
			end

			params[:attendees] ||= []

			@sync_keys = {}
			list_events calendar_id: params[:calendar_id]
			uid = generate_uid

			self.client.debug = true
			
			dt_stamp = DateTime.now
			response = make_request(:create_event_request, {
				sync_key: get_sync_key(params[:calendar_id]),
				collection_id: params[:calendar_id],
				client_id: 1,
				timezone: params[:timezone] || "Atlantic/Reykjavik",
				all_day_event: 0,
				busy_status: 2,
				dt_stamp: dt_stamp.strftime("%Y%m%dT%H%M%SZ"),
				start_time: params[:start_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
				end_time: params[:end_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
				sensitivity: 0,
				location: params[:location],
				subject: params[:summary],
				body: params[:description],
				id: uid,
				meeting_status: 0,
				attendees: params[:attendees]
			})

			if params[:attendees].length > 0
				make_request :send_invitation_request, {
					attendees: params[:attendees],
					subject: params[:summary],
					body: params[:description],
					uid: uid,
					client_id: generate_client_id,
					dt_stamp: dt_stamp,
					start_time: params[:start_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
					end_time: params[:end_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
					start_timezone: params[:timezone] || "Atlantic/Reykjavik",
					end_timezone: params[:timezone] || "Atlantic/Reykjavik"
				}
			end

			{
				event_id: response.css("Add ServerId").text,
				calendar_id: params[:calendar_id],
				uid: uid
			}
		end

		# Delete a user event identified by calendar_id and event_id (required args)
		def delete_event params={}
			@sync_keys = {}
			list_events calendar_id: params[:calendar_id]

			make_request(:delete_event_request, {
					sync_key: get_sync_key(params[:calendar_id]),
					collection_id: params[:calendar_id],
					server_id: params[:event_id]
				})
		end

		# Update a user event identified by calendar_id and event_id (required args)
		def update_event params={}
			[:calendar_id, :event_id, :summary, :start_date, :end_date].each do |key|
				raise "Missing param #{key}" unless params[key]
			end
			@sync_keys = {}
			events = list_events calendar_id: params[:calendar_id]

			event = events.select{|event| event[:server_id] == params[:event_id]}.first
			uid = event[:id]

			params[:attendees] ||= []
			if params[:start_date]
				start_date = params[:start_date].to_time.utc
			else
				start_date = DateTime.parse(event['start']['dateTime'])
			end
			if params[:end_date]
				end_date = params[:end_date].to_time.utc
			else
				end_date = DateTime.parse(event['en']['dateTime'])
			end

			summary = params[:summary] || event[:summary]
			dt_stamp = DateTime.now
			make_request(:update_event_request, {
					sync_key: get_sync_key(params[:calendar_id]),
					server_id: params[:event_id],
					collection_id: params[:calendar_id],
					client_id: 1,
					timezone: params[:timezone] || "Atlantic/Reykjavik",
					all_day_event: 0,
					busy_status: 2,
					dt_stamp: dt_stamp.strftime("%Y%m%dT%H%M%SZ"),
					start_time: start_date.strftime("%Y%m%dT%H%M%SZ"),
					end_time: end_date.strftime("%Y%m%dT%H%M%SZ"),
					sensitivity: 0,
					location: params[:location],
					subject: summary,
					body: params[:description],
					id: uid,
					meeting_status: 0,
					attendees: params[:attendees]
				})

			if params[:attendees].length > 0
				make_request :send_invitation_request, {
					attendees: params[:attendees],
					subject: params[:summary],
					body: params[:description],
					uid: uid,
					client_id: generate_client_id,
					dt_stamp: dt_stamp,
					start_time: params[:start_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
					end_time: params[:end_date].to_time.utc.strftime("%Y%m%dT%H%M%SZ"),
					start_timezone: params[:timezone] || "Atlantic/Reykjavik",
					end_timezone: params[:timezone] || "Atlantic/Reykjavik"
				}
			end
		end

		# Used for test purposes - need a secret.yml file
		def self.example
			secret_data = YAML.load_file("secret.yml")
			self.new({
				username: secret_data['example_username'],
				password: secret_data['example_password'],
				server_url: secret_data['example_server_url'],
				device_id: "JULIEDESK",
				device_type: "Julie",
				policy_key: secret_data['example_policy_key']
				})
		end

		# Used for test purposes - need a secret.yml file
		def self.iphone_example
			secret_data = YAML.load_file("secret.yml")
			self.new({
				username: secret_data['example_username'],
				password: secret_data['example_password'],
				server_url: secret_data['example_server_url'],
				device_id: secret_data['iphone_device_id'],
				device_type: secret_data['iphone_device_type'],
				policy_key: secret_data['iphone_policy_key']
				})
		end

		

		private

		def make_request request, params
			response = client.send(request, params)
			sync_key = response.css("SyncKey").text
			if sync_key.length > 0
				set_sync_key params[:collection_id], sync_key
			end

			response
		end

		def generate_uid
			generate_random_string 30
		end

		def generate_random_string length
			(0...length).map do
			i = rand(26 + 10)
			if i < 26
				(65 + i).chr
			else
				(48 + i-26).chr
			end
			end.join
		end

		def generate_client_id
			[
				generate_random_string(8),
				generate_random_string(4),
				generate_random_string(4),
				generate_random_string(4),
				generate_random_string(12)
			].join("-")
		end

		def parse_event event_item, calendar_id
			result = {
				#timezone: ActiveSync::WbxmlDecoder.decode_timezone_string(event_item.css("Timezone").text),
				'start' => {'dateTime' => DateTime.parse(event_item.css("StartTime").text).to_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")},
				'end' => {'dateTime' => DateTime.parse(event_item.css("EndTime").text).to_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")},
				'summary' => event_item.css("Subject").text,
				'id' => event_item.css("ServerId").text,
				'uid' => event_item.css("UID").text,
				'calId' => calendar_id,
				'description' => "",
				'location' => "",
				'all_day' => false,
				'attendees' => [],
				'recurringEventId' => nil,
				'recurrence' => []
			}

			if event_item.css("Recurrence").first
				result['recurrence'] = {}
				[
					'type',
					'occurrences',
					'interval',
					'week_of_month',
					'day_of_week',
					'month_of_year',
					'until',
					'day_of_month',
					'calendar_type',
					'is_leap_month',
					'first_day_of_week'
				].each do |recurrence_key|
					key_elt = event_item.css("Recurrence #{recurrence_key.to_s.split('_').collect(&:capitalize).join}")
					if key_elt.length > 0
						result['recurrence'][recurrence_key] = key_elt.text
					end
				end
			end

			result
		end

		def parse_deleted_event event_item
			{
				server_id: event_item.css("ServerId").text
			}
		end

		def sync_keys
			@sync_keys ||= {}
		end

		def get_sync_key collection_id
			sync_keys[collection_id] ||= "0"
		end

		def set_sync_key collection_id, sync_key
			sync_keys[collection_id] = sync_key
		end

	    
	end
end