class Wappi::IncomingMessageService
  include FileTypeHelper

  SUPPORTED_TYPES = %w[chat image document audio ptt].freeze

  def initialize(inbox:, event:, outgoing: false)
    @inbox = inbox
    @event = event.with_indifferent_access
    @outgoing = outgoing
  end

  def perform
    return unless @event[:chat_type].blank? || @event[:chat_type] == 'dialog'
    return unless SUPPORTED_TYPES.include?(@event[:type])
    return if @inbox.messages.exists?(source_id: external_message_id)

    set_contact
    set_conversation
    create_message
  end

  private

  def set_contact
    if @inbox.channel.platform == 'max' && phone_number.present?
      phone_source_id = @inbox.channel.source_id_for_phone(phone_number)
      @contact_inbox = @inbox.contact_inboxes.find_by(source_id: phone_source_id)
      @contact_inbox&.update!(source_id: routing_chat_id)
    end

    @contact_inbox ||= ContactInboxWithContactBuilder.new(
      source_id: routing_chat_id,
      inbox: @inbox,
      contact_attributes: {
        name: contact_name,
        additional_attributes: {
          wappi_profile_id: @inbox.channel.profile_id,
          wappi_legacy_chat_id: legacy_chat_id,
          wappi_phone_number: phone_number
        }.compact
      }
    ).perform
    @contact = @contact_inbox.contact
    set_contact_phone_number
  end

  def set_contact_phone_number
    return if phone_number.blank? || @contact.phone_number.present?
    return if @inbox.account.contacts.where.not(id: @contact.id).exists?(phone_number: phone_number)

    @contact.update!(phone_number: phone_number)
  end

  def set_conversation
    @conversation = existing_conversation

    if @conversation
      @conversation.update!(additional_attributes: @conversation.additional_attributes.merge(conversation_attributes))
      return
    end

    @conversation = Conversation.create!(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: conversation_attributes
    )
  end

  def existing_conversation
    conversations = @contact_inbox.conversations
    return conversations.last if @inbox.lock_to_single_conversation

    conversations.where.not(status: :resolved).last
  end

  def conversation_attributes
    {
      'wappi_chat_id' => routing_chat_id,
      'wappi_legacy_chat_id' => legacy_chat_id
    }.compact
  end

  def create_message
    message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: @outgoing ? :outgoing : :incoming,
      status: @outgoing ? :delivered : :sent,
      sender: @outgoing ? nil : @contact,
      source_id: external_message_id,
      content_attributes: content_attributes
    )

    attach_media(message) unless @event[:type] == 'chat'
    message.save!
  end

  def attach_media(message)
    attachment = message.attachments.new(
      account_id: message.account_id,
      file_type: file_type(content_type)
    )

    if @event[:active_storage_blob_id].present?
      attachment.file.attach(ActiveStorage::Blob.find(@event[:active_storage_blob_id]))
    else
      attach_remote_file(attachment)
    end
  end

  def attach_remote_file(attachment)
    SafeFetch.fetch(@event[:file_link], validate_content_type: false) do |result|
      tempfile = Tempfile.new(['wappi-media', file_extension], binmode: true)
      IO.copy_stream(result.tempfile, tempfile)
      tempfile.rewind
      attachment.file.attach(io: tempfile, filename: file_name, content_type: content_type)
    end
  end

  def content_attributes
    attributes = {}
    attributes[:external_echo] = true if @outgoing
    attributes[:wappi_source] = @event[:from_where] if @outgoing

    replied_message = find_replied_message if @event[:isReply] && @event[:stanza_id].present?
    if replied_message
      attributes[:in_reply_to] = replied_message.id
      attributes[:in_reply_to_external_id] = @event[:stanza_id]
    end

    attributes
  end

  def find_replied_message
    @inbox.messages.find_by(source_id: @event[:stanza_id]) ||
      @inbox.messages.where("(external_source_ids #>> '{}')::jsonb @> ?", { wappi_message_ids: [@event[:stanza_id]] }.to_json).first
  end

  def message_content
    @event[:type] == 'chat' ? @event[:body] : @event[:caption]
  end

  def external_message_id
    @event[:id].to_s
  end

  def routing_chat_id
    @event[:whatsapp_chat_id].presence || @event[:chatId].presence || @event[:chat_id]
  end

  def legacy_chat_id
    return unless @inbox.channel.platform == 'whatsapp'

    [@event[:chatId], @event[:chat_id]].compact.find { |id| id.end_with?('@c.us') }
  end

  def contact_name
    names = @outgoing ? [@event[:contact_name], @event[:senderName]] : [@event[:senderName], @event[:contact_name]]
    names = [@event[:contact_name]] if @outgoing && @inbox.channel.platform == 'max'
    names.find(&:present?) || phone_number.presence || routing_chat_id
  end

  def phone_number
    if @inbox.channel.platform == 'max'
      digits = @event[:contact_phone].to_s.gsub(/\D/, '')
      return digits.present? ? "+#{digits}" : nil
    end

    jid = @outgoing ? @event[:to] : @event[:from]
    digits = jid.to_s.delete_suffix('@c.us').gsub(/\D/, '')
    digits.present? ? "+#{digits}" : nil
  end

  def content_type
    @event[:mimetype].to_s.split(';').first.presence || default_content_type
  end

  def default_content_type
    { 'image' => 'image/jpeg', 'audio' => 'audio/mpeg', 'ptt' => 'audio/ogg' }.fetch(@event[:type], 'application/octet-stream')
  end

  def file_extension
    File.extname(@event[:file_name].to_s).presence || Rack::Mime::MIME_TYPES.invert[content_type].presence || '.bin'
  end

  def file_name
    @event[:file_name].presence || "wappi-#{external_message_id}#{file_extension}"
  end
end
