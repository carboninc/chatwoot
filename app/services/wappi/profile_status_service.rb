class Wappi::ProfileStatusService
  def initialize(channel:, event:)
    @channel = channel
    @event = event.with_indifferent_access
  end

  def perform
    @channel.with_lock do
      metadata_key = @event[:wh_type]
      metadata = @channel.status_metadata.merge(metadata_key => @event[:status])
      status = metadata.values.include?('offline') ? 'offline' : 'online'
      reason = if status == 'online'
                 nil
               elsif @event[:status] == 'offline'
                 @event[:reason]
               else
                 @channel.status_reason
               end

      @channel.update!(
        provider_status: status,
        status_reason: reason,
        status_checked_at: Time.current,
        status_metadata: metadata
      )
    end
  end
end
