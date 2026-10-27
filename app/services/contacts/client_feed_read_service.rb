class Contacts::ClientFeedReadService
  pattr_initialize [:conversation!, :message!, :user!]

  def perform
    conversation.with_lock do
      updates = { agent_last_seen_at: [conversation.agent_last_seen_at, message.created_at].compact.max }
      updates[:assignee_last_seen_at] = [conversation.assignee_last_seen_at, message.created_at].compact.max if conversation.assignee_id == user.id
      conversation.update!(updates)
    end
    notify_unread_counts
  end

  private

  def notify_unread_counts
    Conversations::UnreadCounts::Notifier.new(conversation).perform
    Conversations::UnreadCounts::FilteredCountInvalidator.new(conversation.account).conversation_changed!
  end
end
