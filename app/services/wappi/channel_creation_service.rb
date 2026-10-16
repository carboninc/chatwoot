class Wappi::ChannelCreationService
  def initialize(account:, channel_attributes:, inbox_attributes:)
    @account = account
    @channel_attributes = channel_attributes
    @inbox_attributes = inbox_attributes
  end

  def perform
    ActiveRecord::Base.transaction do
      @channel = @account.wappi_channels.create!(@channel_attributes)
      Wappi::HealthService.new(@channel).sync!
      @inbox = @account.inboxes.create!(@inbox_attributes.merge(channel: @channel))
      Wappi::WebhookSetupService.new(@channel).perform
      @webhook_registered = true
    end

    @inbox
  rescue StandardError
    remove_registered_webhook
    raise
  end

  private

  def remove_registered_webhook
    return unless @webhook_registered

    Wappi::WebhookTeardownService.new(@channel).perform
  rescue Wappi::Client::Error
    nil
  end
end
