class Wappi::WebhookTeardownService
  def initialize(channel)
    @channel = channel
  end

  def perform
    Wappi::Client.new(profile_id: @channel.profile_id, api_token: @channel.api_token, platform: @channel.platform).delete_webhook
  end
end
