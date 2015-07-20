require 'spec_helper'

describe "IcloudAccount" do
  before do
    WebMock.disable_net_connect!
  end
  describe "#new" do

    it "should initialize correctly when everything given" do
      icloud_account = MultiCalendar::IcloudAccount.new(
          username: "marck@zuck.com",
          password: "password"
      )
      expect(icloud_account.username).to eq("marck@zuck.com")
      expect(icloud_account.password).to eq("password")
    end

    it "should raise error when password not given" do
      expect {
        MultiCalendar::IcloudAccount.new(
            username: "marck@zuck.com"
        )
      }.to raise_error("Missing argument password")
    end

    it "should raise error when username not given" do
      expect {
        MultiCalendar::IcloudAccount.new(
            password: "password"
        )
      }.to raise_error("Missing argument username")
    end
  end


  context "when credentials not valid" do
    before(:each) do
      @icloud_account = MultiCalendar::IcloudAccount.new(
          username: "marck@zuck.com",
          password: "wrong_password"
      )
      stub_request(:propfind, "https://marck@zuck.com:wrong_password@p01-caldav.icloud.com/").
          with(:body => "<d:propfind xmlns:d=\"DAV:\">\n  <d:prop>\n    <d:current-user-principal/>\n  </d:prop>\n</d:propfind>\n").
          to_return(:status => 404, :body => "")
    end
    it "should return false" do
      expect(@icloud_account.credentials_valid?).to eq(false)
    end
  end

end