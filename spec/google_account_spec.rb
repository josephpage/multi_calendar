require 'spec_helper'

describe "GoogleAccount" do

  describe "#new" do
    it "should initialize correctly when everything given" do
      google_account = MultiCalendar::GoogleAccount.new(
          client_id: "CLIENTID",
          client_secret: "CLIENTSECRET",
          refresh_token: "REFRESHTOKEN"
      )
      expect(google_account.client_id).to eq("CLIENTID")
      expect(google_account.client_secret).to eq("CLIENTSECRET")
      expect(google_account.refresh_token).to eq("REFRESHTOKEN")
    end

    it "should raise error when client_id not given" do
      expect {
        MultiCalendar::GoogleAccount.new(
            client_secret: "CLIENTSECRET",
            refresh_token: "REFRESHTOKEN"
        )
      }.to raise_error("Missing argument client_id")
    end

    it "should raise error when client_secret not given" do
      expect {
        MultiCalendar::GoogleAccount.new(
            client_id: "CLIENTID",
            refresh_token: "REFRESHTOKEN"
        )
      }.to raise_error("Missing argument client_secret")
    end

    it "should raise error when refresh_token not given" do
      expect {
        MultiCalendar::GoogleAccount.new(
            client_id: "CLIENTID",
            client_secret: "CLIENTSECRET"
        )
      }.to raise_error("Missing argument refresh_token")
    end
  end

  describe "instance" do
    before(:each) do
      @google_account = MultiCalendar::GoogleAccount.new({
                                                             client_id: "CLIENTID",
                                                             email: "my@email.com",
                                                             client_secret: "CLIENTSECRET",
                                                             refresh_token: "REFRESHTOKEN"
                                                         })
    end

    describe "#client" do

      context "when @client set" do
        before(:each) do
          @google_account.instance_variable_set(:@client, "client")
        end
        it "should return @client" do
          expect(@google_account.client).to eq("client")
        end

        it "should not call google" do
          expect(Google::APIClient).to_not receive(:new)
          @google_account.client
        end
      end

      context "when @client not set" do
        before(:each) do
          allow_any_instance_of(Signet::OAuth2::Client).to receive(:fetch_access_token!)
          allow_any_instance_of(Signet::OAuth2::Client).to receive(:access_token).and_return("access_token")
        end
        it "should set @client" do
          @google_account.client
          expect(@google_account.instance_variable_get(:@client)).to be_instance_of(Google::APIClient)
        end

        it "should return @client" do
          expect(@google_account.client).to be_instance_of(Google::APIClient)
        end

        it "should set @access_token" do
          @google_account.client
          expect(@google_account.instance_variable_get(:@access_token)).to eq("access_token")
        end
      end
    end

    describe "#service" do
      context "when @service set" do
        before(:each) do
          @google_account.instance_variable_set(:@service, "service")
        end
        it "should return @service" do
          expect(@google_account.service).to eq("service")
        end

        it "should not call google" do
          expect(@google_account).to_not receive(:client)
          @google_account.service
        end
      end

      context "when @service not set" do
        before(:each) do
          allow(@google_account).to receive_message_chain(:client, :discovered_api).and_return("service")
        end
        it "should set @service" do
          @google_account.service
          expect(@google_account.instance_variable_get(:@service)).to eq("service")
        end

        it "should return @service" do
          expect(@google_account.service).to eq("service")
        end
      end
    end

    describe "#refresh_access_token" do
      before(:each) do
        @google_account.instance_variable_set(:@client, Google::APIClient.new)
        expect(@google_account.instance_variable_get(:@client).authorization).to receive(:grant_type=)
        allow_any_instance_of(Signet::OAuth2::Client).to receive(:access_token).and_return("access_token")
      end
      it "should call google" do
        expect(@google_account.instance_variable_get(:@client).authorization).to receive(:fetch_access_token!)
        @google_account.refresh_access_token
      end

      it "should set @access_token" do
        allow_any_instance_of(Signet::OAuth2::Client).to receive(:fetch_access_token!)
        @google_account.refresh_access_token
        expect(@google_account.instance_variable_get(:@access_token)).to eq("access_token")
      end
    end

    describe "#list_calendars" do
      before do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "list",
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                          'items' => [{
                                                          'id' => 'cid1',
                                                          'summary' => "Calendar 1",
                                                          'colorId' => '17',
                                                          "time_zone" => "Europe/Paris"
                                                      },{
                                                          'id' => 'cid2',
                                                          'summary' => "Calendar 2",
                                                          'colorId' => '42',
                                                          "time_zone" => "America/Los_Angeles"
                                                      }
                                          ]
                                      })
                                  )
        allow(@google_account).to receive_message_chain(:service, :calendar_list, :list).and_return "list"
      end

      it "should list calendars" do
        expect(@google_account.list_calendars()).to eq([{
                                                            :id => 'cid1',
                                                            :summary => "Calendar 1",
                                                            :colorId => '17',
                                                            :timezone => "Europe/Paris"
                                                        },{
                                                            :id => 'cid2',
                                                            :summary => "Calendar 2",
                                                            :colorId => '42',
                                                            :timezone => "America/Los_Angeles"
                                                        }
                                                       ])
      end
    end

    describe "#list_events" do
      before do

        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "list",
            :parameters => {
                :calendarId => "cid1",
                :timeMin => "2015-01-01T00:00:00+00:00",
                :timeMax => "2015-01-30T00:00:00+00:00",
                :singleEvents => true,
                :maxResults => 2500
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                        'timeZone' => "Europe/Paris",
                                        'items' => [{
                                                        'id' => 'eid1',
                                                        'summary' => "Event",
                                                        'description' => "Notes",
                                                        'location' => "Paris",
                                                        'attendees' => [
                                                            {
                                                                'email' => 'john@doe.com',
                                                                'displayName' => "john Doe"
                                                            },
                                                            {
                                                                'email' => 'mark@zuck.com',
                                                                'displayName' => "Mark Zuck"
                                                            }
                                                        ],
                                                        'organizer' => {
                                                            'self' => true
                                                        },
                                                        'visibility' => 'default',
                                                        'start' => {
                                                            'dateTime' => "2015-01-31T12:00:00Z"
                                                        },
                                                        'end' => {
                                                            'dateTime' => "2015-01-31T13:00:00Z"
                                                        },
                                                        'recurringEventId' => nil,
                                                        'recurrence' => []
                                                    }]
                                      })
                                  )

        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "list",
            :parameters => {
                :calendarId => "cid2",
                :timeMin => "2015-01-01T00:00:00+00:00",
                :timeMax => "2015-01-30T00:00:00+00:00",
                :singleEvents => true,
                :maxResults => 2500
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                          'timeZone' => "Europe/Paris",
                                          'items' => [{
                                                          'id' => 'eid2',
                                                          'summary' => "Event",
                                                          'description' => "Notes",
                                                          'location' => "Paris",
                                                          'attendees' => [],
                                                          'organizer' => {
                                                              'self' => false
                                                          },
                                                          'visibility' => 'private',
                                                          'start' => {
                                                              'dateTime' => "2015-01-31T12:00:00Z"
                                                          },
                                                          'end' => {
                                                              'dateTime' => "2015-01-31T13:00:00Z"
                                                          }
                                                      }, {
                                              'id' => 'eid3',
                                              'summary' => "Event",
                                              'description' => "Notes",
                                              'location' => "Paris",
                                              'attendees' => [
                                                  {
                                                      'email' => 'john@doe.com',
                                                      'displayName' => "john Doe"
                                                  },
                                                  {
                                                      'email' => 'mark@zuck.com',
                                                      'displayName' => "Mark Zuck"
                                                  }
                                              ],
                                              'organizer' => {
                                                  'self' => true
                                              },
                                              'visibility' => 'default',
                                              'start' => {
                                                  'dateTime' => "2015-01-31T12:00:00Z"
                                              },
                                              'end' => {
                                                  'dateTime' => "2015-01-31T13:00:00Z"
                                              },
                                              'recurringEventId' => nil,
                                              'recurrence' => []
                                          }]
                                      })
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :list).and_return "list"
      end
      it "should list events" do
        expect(@google_account.list_events({
                                               calendar_ids: ["cid1", "cid2"],
                                               start_date: DateTime.new(2015, 1,1),
                                               end_date: DateTime.new(2015, 1,30)
                                           })).to eq([
                                                                 {
                                                                     'id'=>"eid1",
                                                                     'summary'=>"Event",
                                                                     'description'=>"Notes",
                                                                     'location'=>"Paris",
                                                                     'start'=> {
                                                                         'dateTime' => "2015-01-31T12:00:00Z"
                                                                     },
                                                                     'end'=> {
                                                                         'dateTime' => "2015-01-31T13:00:00Z"
                                                                     },
                                                                     'calId'=>"cid1",
                                                                     'all_day'=>false,
                                                                     'private'=>false,
                                                                     'owned' => true,
                                                                     'attendees'=>[
                                                                         {:email=>"john@doe.com", :name=>"john Doe"},
                                                                         {:email=>"mark@zuck.com", :name=>"Mark Zuck"}
                                                                     ],
                                                                     'recurringEventId' => nil,
                                                                     'recurrence' => []
                                                                 },
                                                                 {
                                                                     'id'=>"eid2",
                                                                     'summary'=>"Event",
                                                                     'description'=>"Notes",
                                                                     'location'=>"Paris",
                                                                     'start'=> {
                                                                         'dateTime' => "2015-01-31T12:00:00Z"
                                                                     },
                                                                     'end'=> {
                                                                         'dateTime' => "2015-01-31T13:00:00Z"
                                                                     },
                                                                     'calId'=>"cid2",
                                                                     'all_day'=>false,
                                                                     'private'=>true,
                                                                     'owned' => false,
                                                                     'attendees'=>[],
                                                                     'recurringEventId' => nil,
                                                                     'recurrence' => []
                                                                 },
                                                                 {
                                                                     'id'=>"eid3",
                                                                     'summary'=>"Event",
                                                                     'description'=>"Notes",
                                                                     'location'=>"Paris",
                                                                     'start'=> {
                                                                         'dateTime' => "2015-01-31T12:00:00Z"
                                                                     },
                                                                     'end'=> {
                                                                         'dateTime' => "2015-01-31T13:00:00Z"
                                                                     },
                                                                     'calId'=>"cid2",
                                                                     'all_day'=>false,
                                                                     'private'=>false,
                                                                     'owned' => true,
                                                                     'attendees'=>[
                                                                         {:email=>"john@doe.com", :name=>"john Doe"},
                                                                         {:email=>"mark@zuck.com", :name=>"Mark Zuck"}
                                                                     ],
                                                                     'recurringEventId' => nil,
                                                                     'recurrence' => []
                                                                 }
                                                     ])
      end
    end

    describe "#get_event" do
      before do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "get",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid1",
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                            'id' => 'eid1',
                                            'summary' => "Event",
                                            'description' => "Notes",
                                            'location' => "Paris",
                                            'attendees' => [
                                                {
                                                    'email' => 'john@doe.com',
                                                    'displayName' => "john Doe"
                                                },
                                                {
                                                    'email' => 'mark@zuck.com',
                                                    'displayName' => "Mark Zuck"
                                                }
                                            ],
                                            'organizer' => {
                                                'self' => true
                                            },
                                            'visibility' => 'default',
                                            'start' => {
                                                'dateTime' => "2015-01-31T12:00:00Z"
                                            },
                                            'end' => {
                                                'dateTime' => "2015-01-31T13:00:00Z"
                                            },
                                            'recurringEventId' => nil,
                                            'recurrence' => []
                                      })
                                  )
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "get",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid2",
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                          'id' => 'eid2',
                                          'summary' => "Event",
                                          'description' => "Notes",
                                          'location' => "Paris",
                                          'attendees' => [
                                              {
                                                  'email' => 'john@doe.com',
                                                  'displayName' => "john Doe"
                                              },
                                              {
                                                  'email' => 'mark@zuck.com',
                                                  'displayName' => "Mark Zuck"
                                              }
                                          ],
                                          'status' => "cancelled",
                                          'organizer' => {
                                              'self' => true
                                          },
                                          'visibility' => 'default',
                                          'start' => {
                                              'dateTime' => "2015-01-31T12:00:00Z"
                                          },
                                          'end' => {
                                              'dateTime' => "2015-01-31T13:00:00Z"
                                          },
                                          'recurringEventId' => nil,
                                          'recurrence' => []
                                      })
                                  )
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "get",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid3",
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: {
                                          'error' => {'message' => 'Not Found'}
                                      })
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :get).and_return "get"
      end
      context "Normal event" do
        it "should get an event" do
          expect(@google_account.get_event({
                                               calendar_id: "cid1",
                                               event_id: "eid1"
                                           })).to eq({
                                                         'id'=>"eid1",
                                                         'summary'=>"Event",
                                                         'description'=>"Notes",
                                                         'location'=>"Paris",
                                                         'start'=> {
                                                             'dateTime' => "2015-01-31T12:00:00Z"
                                                         },
                                                         'end'=> {
                                                             'dateTime' => "2015-01-31T13:00:00Z"
                                                         },
                                                         'calId'=>"cid1",
                                                         'all_day'=>false,
                                                         'private'=>false,
                                                         'owned' => true,
                                                         'attendees'=>[
                                                             {:email=>"john@doe.com", :name=>"john Doe"},
                                                             {:email=>"mark@zuck.com", :name=>"Mark Zuck"}
                                                         ],
                                                         'recurringEventId' => nil,
                                                         'recurrence' => []
                                                     })
        end
      end
      context "Event deleted" do
        it "should raise" do
          expect{@google_account.get_event({
                                               calendar_id: "cid1",
                                               event_id: "eid2"
                                           })}.to raise_error(MultiCalendar::EventNotFoundException)
        end
      end

      context "No event" do
        it "should raise" do
          expect{@google_account.get_event({
                                             calendar_id: "cid1",
                                             event_id: "eid3"
                                         })}.to raise_error(MultiCalendar::EventNotFoundException)
        end
      end

    end

    describe "#create_event without attendees" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "insert",
            :parameters => {
                :calendarId => "cid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :dateTime => "2015-01-01T12:00:00+00:00"
                },
                :end => {
                    :dateTime => "2015-01-01T13:00:00+00:00"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :insert).and_return "insert"
      end

      it "should create event without attendees" do
        expect(@google_account.create_event({
                                                calendar_id: 'cid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [],
                                                location: "Paris"
                                            }
               )).to eq({
                  event_id: "eid1",
                  calendar_id: "cid1",
                  event_url: ""
                        })
      end
    end

    describe "#create_event with attendees" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "insert",
            :parameters => {
                :calendarId => "cid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :dateTime => "2015-01-01T12:00:00+00:00"
                },
                :end => {
                    :dateTime => "2015-01-01T13:00:00+00:00"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [
                    {:email => "you@yourdomain.com"},
                    {:email => "my@email.com", :responseStatus => "accepted"}
                ],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :insert).and_return "insert"
      end

      it "should create event with attendees" do
        expect(@google_account.create_event({
                                                calendar_id: 'cid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [{email: "you@yourdomain.com"}],
                                                location: "Paris"
                                            }
               )).to eq({
                                    event_id: "eid1",
                                    calendar_id: "cid1",
                                    event_url: ""
                                })
      end
    end

    describe "#create_event all_day" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "insert",
            :parameters => {
                :calendarId => "cid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :date => "2015-01-01"
                },
                :end => {
                    :date => "2015-01-01"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :insert).and_return "insert"
      end

      it "should create event with attendees" do
        expect(@google_account.create_event({
                                                calendar_id: 'cid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                all_day: true,
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [],
                                                location: "Paris"
                                            }
               )).to eq({
                                    event_id: "eid1",
                                    calendar_id: "cid1",
                                    event_url: ""
                                })
      end
    end

    describe "#update_event with attendees" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "update",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :dateTime => "2015-01-01T12:00:00+00:00"
                },
                :end => {
                    :dateTime => "2015-01-01T13:00:00+00:00"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [
                    {:email => "you@yourdomain.com"},
                    {:email => "my@email.com", :responseStatus => "accepted"}
                ],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :update).and_return "update"
      end

      it "should update event with attendees" do
        expect(@google_account.update_event({
                                                calendar_id: 'cid1',
                                                event_id: 'eid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [{email: "you@yourdomain.com"}],
                                                location: "Paris"
                                            }
               )).to eq("eid1")
      end
    end

    describe "#update_event without attendees" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "update",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :dateTime => "2015-01-01T12:00:00+00:00"
                },
                :end => {
                    :dateTime => "2015-01-01T13:00:00+00:00"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :update).and_return "update"
      end

      it "should update event without attendees" do
        expect(@google_account.update_event({
                                                calendar_id: 'cid1',
                                                event_id: 'eid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [],
                                                location: "Paris"
                                            }
               )).to eq("eid1")
      end
    end

    describe "#update_event all_day" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "update",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid1",
                :sendNotifications => true
            },
            body_object: {
                :start => {
                    :date => "2015-01-01"
                },
                :end => {
                    :date => "2015-01-01"
                },
                :summary => "New event",
                :location => "Paris",
                :visibility => "default",
                :attendees => [],
                :description => "created by Multi-Calendar gem"
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", data: double("data", id: "eid1"))
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :update).and_return "update"
      end

      it "should update event without attendees" do
        expect(@google_account.update_event({
                                                calendar_id: 'cid1',
                                                event_id: 'eid1',
                                                start_date: DateTime.new(2015, 1, 1, 12, 0),
                                                end_date: DateTime.new(2015, 1, 1, 13, 0),
                                                all_day: true,
                                                summary: "New event",
                                                description: "created by Multi-Calendar gem",
                                                attendees: [],
                                                location: "Paris"
                                            }
               )).to eq("eid1")
      end
    end

    describe "#delete_event" do
      before(:each) do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "delete",
            :parameters => {
                :calendarId => "cid1",
                :eventId => "eid1",
                :sendNotifications => true
            },
            :headers => {"Content-Type" => "application/json"}
        })).and_return(
                                      double("response", body: "")
                                  )
        allow(@google_account).to receive_message_chain(:service, :events, :delete).and_return "delete"
      end

      it "should delete event" do
        expect(@google_account.delete_event({
                                                calendar_id: 'cid1',
                                                event_id: 'eid1'
                                            })).to eq(true)
      end
    end

    describe "#share_calendar_with" do
      before do
        allow(@google_account).to receive_message_chain(:client, :execute).with(({
            :api_method => "insert",
            :parameters => {
                :calendarId => "cid1",
            },
            :body_object => {
                role: "writer",
                scope: {
                    type: "user",
                    value: "mark@zuck.com"
                }
            },
            :headers => {"Content-Type" => "application/json"}
        }))
        allow(@google_account).to receive_message_chain(:service, :acl, :insert).and_return "insert"
      end
      it "should share calendar with email" do
        @google_account.share_calendar_with({
            calendar_id: "cid1",
            email: "mark@zuck.com"
                                            })
      end
    end
  end

end
