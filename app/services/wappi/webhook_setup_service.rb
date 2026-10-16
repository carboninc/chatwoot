class Wappi::WebhookSetupService
  WEBHOOK_TYPES = %w[
    incoming_message
    delivery_status
    authorization_status
    application_status
    outgoing_message_api
    outgoing_message_phone
  ].freeze

  def initialize(channel, cleanup_on_failure: true)
    @channel = channel
    @cleanup_on_failure = cleanup_on_failure
  end

  def perform
    client.set_webhook(url: @channel.webhook_url, secret: @channel.webhook_secret)
    client.configure_webhook_types(WEBHOOK_TYPES)
  rescue Wappi::Client::Error
    safely_remove_webhook if @cleanup_on_failure
    raise
  end

  private

  def client
    @client ||= Wappi::Client.new(profile_id: @channel.profile_id, api_token: @channel.api_token, platform: @channel.platform)
  end

  def safely_remove_webhook
    client.delete_webhook
  rescue Wappi::Client::Error
    nil
  end
end
