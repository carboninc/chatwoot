# Queries shared by the client list, timeline and send boundary.
class Contacts::ClientFeed
  PAGE_SIZE = 50

  pattr_initialize [:account!, :user!]

  def inboxes
    user.assigned_inboxes.where(account_id: account.id, channel_type: 'Channel::Wappi').preload(:channel)
  end

  def conversations
    Conversations::PermissionFilterService.new(
      account.conversations.where(inbox_id: account.inboxes.where(channel_type: 'Channel::Wappi')),
      user, account
    ).perform
  end

  def contacts
    with_history = account.contacts.where(id: conversations.select(:contact_id))
    with_channel = account.contacts.where(id: ContactInbox.where(inbox_id: inboxes).select(:contact_id))
    result = with_history.or(with_channel)
    return result unless inboxes.exists?

    result.or(account.contacts.where.not(phone_number: [nil, '']))
  end

  def search(query)
    return contacts if query.blank?

    pattern = "%#{Contact.sanitize_sql_like(query)}%"
    table = Contact.arel_table
    contacts.where(table[:name].matches(pattern).or(table[:phone_number].matches(pattern)).or(table[:email].matches(pattern)))
  end

  def contact_conversations(contact)
    conversations.where(contact_id: contact.id).includes(:assignee, :team, :contact, :contact_inbox, inbox: :channel)
  end

  def messages(contact)
    Message.where(conversation_id: contact_conversations(contact).select(:id), account_id: account.id)
           .includes(:conversation)
  end

  def sent_message(contact, request_id)
    request = ClientFeedRequest.find_by(account_id: account.id, user_id: user.id, request_id: request_id)
    messages(contact).find(request.message_id) if request
  end

  def message_page(contact, before: nil, after: nil)
    scope = messages(contact).preload(:sender, attachments: { file_attachment: :blob })
    scope = messages_at_cursor(scope, before || after, after.present?) if before || after
    direction = after.present? ? :asc : :desc
    page = scope.reorder(created_at: direction, id: direction).limit(PAGE_SIZE + 1).to_a
    has_more = page.size > PAGE_SIZE
    page = page.first(PAGE_SIZE)
    page.reverse! if direction == :desc
    [page, has_more]
  end

  def latest_reply_conversation_id(contact)
    online_inboxes = inboxes.where(channel_id: account.wappi_channels.where(provider_status: 'online').select(:id))
    messages(contact).incoming.where(private: false, inbox_id: online_inboxes)
                     .reorder(created_at: :desc, id: :desc).first&.conversation&.display_id
  end

  def contactable_inboxes(contact)
    allowed_ids = inboxes.ids
    Contacts::ContactableInboxesService.new(contact: contact).get.select do |entry|
      entry[:inbox].wappi? && allowed_ids.include?(entry[:inbox].id)
    end
  end

  private

  def messages_at_cursor(scope, cursor_id, after)
    cursor = scope.find(cursor_id)
    table = Message.arel_table
    timestamp = after ? table[:created_at].gt(cursor.created_at) : table[:created_at].lt(cursor.created_at)
    id = after ? table[:id].gt(cursor.id) : table[:id].lt(cursor.id)
    scope.where(timestamp.or(table[:created_at].eq(cursor.created_at).and(id)))
  end
end
