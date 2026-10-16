class Webhooks::WappiController < ActionController::API
  before_action :set_channel
  before_action :authenticate_webhook
  before_action :validate_payload

  def process_payload
    payload = Wappi::WebhookPayloadNormalizer.new(@payload).perform
    Webhooks::WappiEventsJob.perform_later(channel_id: @channel.id, payload: payload)
    head :ok
  rescue ArgumentError
    head :unprocessable_entity
  end

  private

  def set_channel
    @channel = Channel::Wappi.find_by!(platform: params[:platform], profile_id: params[:profile_id])
  end

  def authenticate_webhook
    provided_secret = request.headers['Authorization'].to_s
    head :unauthorized unless provided_secret.present? && ActiveSupport::SecurityUtils.secure_compare(provided_secret, @channel.webhook_secret)
  end

  def validate_payload
    @payload = JSON.parse(request.raw_post)
    events = @payload['messages']
    events = [events] if events.is_a?(Hash)

    head :unprocessable_entity unless events.is_a?(Array) && events.all? do |event|
      event.is_a?(Hash) && event['profile_id'] == @channel.profile_id
    end
  rescue JSON::ParserError
    head :unprocessable_entity
  end
end
