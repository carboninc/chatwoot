class Wappi::WebhookPayloadNormalizer
  SUPPORTED_MEDIA_TYPES = %w[image document audio ptt].freeze
  MAX_OFFLINE_STATUSES = %w[ACCOUNT_SPAM_RESTRICTED CHECK_PHONE_FLOODWAIT].freeze
  BINARY_TYPES = %w[image document audio ptt video sticker].freeze
  EVENT_KEYS = %w[
    wh_type profile_id id task_id status detail reason type body caption from to senderName senderLastName
    contact_name contact_last_name contact_phone chatId chat_id whatsapp_chat_id chat_type from_where isReply stanza_id
    wappi_bot_id file_link file_name mimetype
  ].freeze

  def initialize(payload, platform:)
    @payload = payload
    @platform = platform
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
    normalize_max_event(normalized_event) if @platform == 'max'
    normalize_media(normalized_event)
    normalized_event
  end

  def normalize_max_event(event)
    event['type'] = 'chat' if event['type'] == 'text'
    event['chat_type'] = 'dialog' if event['chat_type'] == 'user'
    chat_id = event['chatId'].presence || event['chat_id']
    event['chat_type'] = 'group' if chat_id.to_s.start_with?('-')
    event['senderName'] = [event['senderName'], event.delete('senderLastName')].compact_blank.join(' ')
    event['contact_name'] = [event['contact_name'], event.delete('contact_last_name')].compact_blank.join(' ')
    normalize_max_status(event)
  end

  def normalize_max_status(event)
    return unless event['wh_type'] == 'authorization_status' && MAX_OFFLINE_STATUSES.include?(event['status'])

    event['reason'] = event['reason'].presence || event['status']
    event['status'] = 'offline'
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
