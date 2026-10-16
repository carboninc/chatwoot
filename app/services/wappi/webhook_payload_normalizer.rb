class Wappi::WebhookPayloadNormalizer
  SUPPORTED_MEDIA_TYPES = %w[image document audio ptt].freeze
  BINARY_TYPES = %w[image document audio ptt video sticker].freeze
  EVENT_KEYS = %w[
    wh_type profile_id id task_id status detail reason type body caption from to senderName contact_name
    chatId chat_id whatsapp_chat_id chat_type from_where isReply stanza_id wappi_bot_id file_link file_name mimetype
  ].freeze

  def initialize(payload)
    @payload = payload
  end

  def perform
    { 'messages' => events.map { |event| normalize_event(event) } }
  rescue StandardError
    @created_blobs&.each(&:purge_later)
    raise
  end

  private

  def events
    messages = @payload['messages']
    messages.is_a?(Array) ? messages : [messages]
  end

  def normalize_event(event)
    normalized_event = event.slice(*EVENT_KEYS).deep_dup
    normalize_media(normalized_event)
    normalized_event
  end

  def normalize_media(event)
    return unless BINARY_TYPES.include?(event['type'])
    return event.delete('body') unless SUPPORTED_MEDIA_TYPES.include?(event['type'])
    return event.delete('body') if event['file_link'].present?
    return if event['body'].blank?

    stage_embedded_media(event)
  end

  def stage_embedded_media(event)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(Base64.strict_decode64(event['body'])),
      filename: event['file_name'].presence || "wappi-#{event['id']}",
      content_type: event['mimetype'].to_s.split(';').first.presence || 'application/octet-stream'
    )
    (@created_blobs ||= []) << blob
    event['active_storage_blob_id'] = blob.id
    event.delete('body')
  end
end
