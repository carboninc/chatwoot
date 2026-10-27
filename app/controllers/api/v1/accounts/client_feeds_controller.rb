class Api::V1::Accounts::ClientFeedsController < Api::V1::Accounts::BaseController
  before_action :set_feed
  before_action :set_contact, except: :index

  def index
    validate_integer_parameter(:page) if params.key?(:page)
    raise ActionController::ParameterMissing, :q if params.key?(:q) && !params[:q].is_a?(String)

    @contacts = @feed.search(params[:q]).preload(avatar_attachment: :blob)
                     .order(last_activity_at: :desc, id: :desc).page(params[:page]).per(Contacts::ClientFeed::PAGE_SIZE)
  end

  def show
    @conversations = @feed.contact_conversations(@contact).order(last_activity_at: :desc, id: :desc)
    @channels = @feed.contactable_inboxes(@contact)
    @default_conversation_id = @feed.latest_reply_conversation_id(@contact)
  end

  def messages
    validate_integer_parameter(:before) if params.key?(:before)
    validate_integer_parameter(:after) if params.key?(:after)
    raise ActionController::ParameterMissing, :before if params.key?(:before) && params.key?(:after)

    @messages, @has_more = @feed.message_page(@contact, before: params[:before], after: params[:after])
  end

  def create_message
    validate_send_parameters
    @message = @feed.sent_message(@contact, params[:request_id]) || send_message
    render partial: 'api/v1/accounts/client_feeds/message', locals: { message: @message }
  end

  def read
    validate_integer_parameter(:message_id, json: true)
    message = @feed.messages(@contact).find(params[:message_id])
    Contacts::ClientFeedReadService.new(conversation: message.conversation, message: message, user: Current.user).perform
    head :ok
  end

  private

  def set_feed
    @feed = Contacts::ClientFeed.new(account: Current.account, user: Current.user)
  end

  def set_contact
    @contact = Current.account.contacts.find(params[:id])
    authorize @contact, :show?
  end

  def send_message
    conversation, channel = send_target
    validate_reply(conversation)
    Contacts::ClientFeedSendService.new(
      contact: @contact, user: Current.user, conversation: conversation, channel: channel, params: params
    ).perform
  end

  def send_target
    if params[:conversation_id].present?
      raise ActionController::ParameterMissing, :inbox_id if params[:inbox_id].present?

      conversation = @feed.contact_conversations(@contact).find_by!(display_id: params[:conversation_id])
      inbox = conversation.inbox
    else
      channel = @feed.contactable_inboxes(@contact).find { |entry| entry[:inbox].id.to_s == params[:inbox_id] }
      raise ActionController::ParameterMissing, :inbox_id unless channel

      inbox = channel[:inbox]
    end
    raise ActionController::ParameterMissing, :channel_offline unless inbox.channel.online?

    [conversation, channel]
  end

  def validate_reply(conversation)
    return if params[:in_reply_to].blank?

    raise ActionController::ParameterMissing, :in_reply_to unless conversation

    reply = conversation.messages.find(params[:in_reply_to])
    raise ActionController::ParameterMissing, :in_reply_to if reply.private? || reply.source_id.blank?
  end

  def validate_integer_parameter(key, json: false)
    value = params[key]
    valid = json ? value.is_a?(Integer) && value.positive? : value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)
    raise ActionController::ParameterMissing, key unless valid
  end

  def validate_send_parameters
    validate_request_id
    raise ActionController::ParameterMissing, :content unless params[:content].is_a?(String)
    raise ActionController::ParameterMissing, :content if params[:content].blank? && params[:attachments].blank?

    [:conversation_id, :inbox_id, :in_reply_to].each do |key|
      validate_integer_parameter(key) if params.key?(key)
    end
    validate_attachments if params.key?(:attachments)
  end

  def validate_request_id
    request_id = params[:request_id]
    uuid_pattern = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    raise ActionController::ParameterMissing, :request_id unless request_id.is_a?(String) && request_id.match?(uuid_pattern)
  end

  def validate_attachments
    attachments = params[:attachments]
    return if attachments.is_a?(Array) && attachments.all?(ActionDispatch::Http::UploadedFile)

    raise ActionController::ParameterMissing, :attachments
  end
end
