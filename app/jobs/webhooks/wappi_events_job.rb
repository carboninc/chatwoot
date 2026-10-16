class Webhooks::WappiEventsJob < MutexApplicationJob
  queue_as :low
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 10

  def perform(channel_id:, payload:)
    @channel = Channel::Wappi.find(channel_id)
    events(payload).each do |event|
      event = event.with_indifferent_access
      process_event(event)
      purge_unattached_blob(event)
    end
  end

  private

  def events(payload)
    messages = payload['messages'] || payload[:messages]
    messages.is_a?(Array) ? messages : [messages]
  end

  def process_event(event)
    case event[:wh_type]
    when 'incoming_message'
      process_message(event, outgoing: false)
    when 'outgoing_message_phone', 'outgoing_message_api'
      process_outgoing_message(event)
    when 'delivery_status'
      Wappi::DeliveryStatusService.new(inbox: @channel.inbox, event: event).perform
    when 'authorization_status', 'application_status'
      Wappi::ProfileStatusService.new(channel: @channel, event: event).perform
    else
      Rails.logger.info("[WAPPI] Ignored webhook type=#{event[:wh_type]} message_id=#{event[:id]} channel_id=#{@channel.id}")
    end
  end

  def process_outgoing_message(event)
    return if Wappi::OutgoingEchoService.new(inbox: @channel.inbox, event: event).correlate?

    process_message(event, outgoing: true)
  end

  def process_message(event, outgoing:)
    return if event[:id].blank?

    lock_key = "wappi:message:#{@channel.id}:#{Digest::SHA256.hexdigest(event[:id].to_s)}"
    with_lock(lock_key, 30.seconds) do
      Wappi::IncomingMessageService.new(inbox: @channel.inbox, event: event, outgoing: outgoing).perform
    end
  end

  def purge_unattached_blob(event)
    return if event[:active_storage_blob_id].blank?

    blob = ActiveStorage::Blob.find_by(id: event[:active_storage_blob_id])
    blob&.purge_later unless blob&.attachments&.exists?
  end
end
