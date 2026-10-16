class Wappi::ChannelUpdateService
  def initialize(channel, attributes)
    @channel = channel
    @attributes = attributes
  end

  def perform
    @channel.assign_attributes(@attributes)
    health = Wappi::HealthService.new(@channel).fetch
    Wappi::WebhookSetupService.new(@channel, cleanup_on_failure: false).perform
    @channel.update!(
      provider_status: health[:status],
      status_reason: health[:reason],
      status_checked_at: Time.current,
      status_metadata: {
        'authorization_status' => health[:authorized] == true ? 'online' : 'offline',
        'application_status' => health[:app_status] == 'open' ? 'online' : 'offline'
      }
    )
  end
end
