class Wappi::SendOnWappiService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Wappi
  end

  def perform_reply
    return mark_failed('Wappi profile is offline') unless channel.online?

    responses = message.attachments.present? ? send_attachments : [send_text]
    store_external_ids(responses)
  rescue Wappi::Client::Error => e
    mark_failed(e.message)
  end

  def send_text
    return client.reply(message_id: reply_message_id, body: message.outgoing_content, bot_id: bot_id(0)) if reply_message_id.present?

    client.send_text(recipient: recipient, body: message.outgoing_content, bot_id: bot_id(0))
  end

  def send_attachments
    message.attachments.each_with_index.map { |attachment, index| send_attachment(attachment, index) }
  end

  def send_attachment(attachment, index)
    return send_reply_attachment(attachment, index) if index.zero? && reply_message_id.present?

    client.send_file(
      recipient: recipient,
      url: attachment.download_url,
      caption: index.zero? ? message.outgoing_content : nil,
      file_name: attachment.file.filename.to_s,
      bot_id: bot_id(index)
    )
  end

  def send_reply_attachment(attachment, index)
    client.reply(
      message_id: reply_message_id,
      body: message.outgoing_content.to_s,
      url: attachment.download_url,
      bot_id: bot_id(index)
    )
  end

  def store_external_ids(responses)
    message_ids = responses.map do |response|
      response['message_id'].presence || raise(Wappi::Client::ApiError, 'Wappi response does not contain a message ID')
    end
    message.update!(source_id: message.source_id.presence || message_ids.first, external_source_ids: merged_external_ids(responses, message_ids))
  end

  def merged_external_ids(responses, message_ids)
    task_ids = responses.filter_map { |response| response['task_id'] }
    external_ids = message.external_source_ids.to_h
    external_ids['wappi_message_ids'] = (Array(external_ids['wappi_message_ids']) + message_ids).uniq
    external_ids['wappi_task_ids'] = (Array(external_ids['wappi_task_ids']) + task_ids).uniq
    external_ids
  end

  def mark_failed(error)
    Messages::StatusUpdateService.new(message, 'failed', error).perform
  end

  def reply_message_id
    message.content_attributes['in_reply_to_external_id']
  end

  def recipient
    value = conversation.additional_attributes['wappi_chat_id'].presence || contact_inbox.source_id
    return value if value.to_s.end_with?('@lid')

    value.to_s.gsub(/\D/, '')
  end

  def bot_id(index)
    "cw:#{message.id}:#{index}"
  end

  def client
    @client ||= Wappi::Client.new(profile_id: channel.profile_id, api_token: channel.api_token, platform: channel.platform)
  end
end
