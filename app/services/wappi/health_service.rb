class Wappi::HealthService
  def initialize(channel)
    @channel = channel
  end

  def fetch
    response = client.status
    online = response['authorized'] == true && response['app_status'] == 'open'

    {
      status: online ? 'online' : 'offline',
      reason: online ? nil : response['reason'].presence || response['detail'].presence,
      authorized: response['authorized'],
      app_status: response['app_status'],
      platform: response['platform']
    }
  end

  def sync!
    health = fetch
    @channel.update!(
      provider_status: health[:status],
      status_reason: health[:reason],
      status_checked_at: Time.current,
      status_metadata: {
        'authorization_status' => health[:authorized] == true ? 'online' : 'offline',
        'application_status' => health[:app_status] == 'open' ? 'online' : 'offline'
      }
    )
    health
  end

  private

  def client
    Wappi::Client.new(profile_id: @channel.profile_id, api_token: @channel.api_token, platform: @channel.platform)
  end
end
