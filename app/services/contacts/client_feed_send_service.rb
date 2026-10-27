class Contacts::ClientFeedSendService
  pattr_initialize [:contact!, :user!, :conversation, :channel, :params!]

  def perform
    contact.with_lock do
      message = existing_message
      return message if message

      target = conversation || create_conversation
      message = build_message(target)
      ClientFeedRequest.create!(account_id: contact.account_id, user_id: user.id, request_id: params[:request_id], message: message)
      message
    end
  end

  private

  def existing_message
    request = ClientFeedRequest.find_by(account_id: contact.account_id, user_id: user.id, request_id: params[:request_id])
    return unless request

    raise ActionController::ParameterMissing, :request_id unless request.message.conversation.contact_id == contact.id

    request.message
  end

  def build_message(target)
    message_params = ActionController::Parameters.new(
      content: params[:content], attachments: params[:attachments],
      content_attributes: { in_reply_to: params[:in_reply_to] }, private: false
    )
    Messages::MessageBuilder.new(user, target, message_params).perform
  end

  def create_conversation
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: channel[:inbox], source_id: channel[:source_id]).perform
    ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
  end
end
