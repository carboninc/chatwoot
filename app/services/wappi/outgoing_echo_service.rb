class Wappi::OutgoingEchoService
  BOT_ID_PATTERN = /\Acw:(\d+):(\d+)\z/

  def initialize(inbox:, event:)
    @inbox = inbox
    @event = event.with_indifferent_access
  end

  def correlate?
    match = BOT_ID_PATTERN.match(@event[:wappi_bot_id].to_s)
    return false unless match

    message = @inbox.messages.find_by(id: match[1])
    return false if message.blank?

    message.with_lock do
      message.update!(source_id: message.source_id.presence || @event[:id], external_source_ids: merged_external_ids(message))
      update_conversation_routing(message)
    end

    true
  end

  private

  def merged_external_ids(message)
    external_ids = message.external_source_ids.to_h
    external_ids['wappi_message_ids'] = (Array(external_ids['wappi_message_ids']) + [@event[:id]]).compact.uniq
    external_ids['wappi_task_ids'] = (Array(external_ids['wappi_task_ids']) + [@event[:task_id]]).compact.uniq
    external_ids
  end

  def update_conversation_routing(message)
    chat_id = @event[:whatsapp_chat_id].presence
    return if chat_id.blank?

    conversation = message.conversation
    conversation.update!(additional_attributes: conversation.additional_attributes.merge('wappi_chat_id' => chat_id))
    conversation.contact_inbox.update!(source_id: chat_id) unless conversation.contact_inbox.source_id == chat_id
  end
end
