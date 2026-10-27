# Keeps successful sends idempotent even when the HTTP response is lost.
# == Schema Information
#
# Table name: client_feed_requests
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  message_id :bigint           not null
#  request_id :string           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_client_feed_requests_on_message_id  (message_id) UNIQUE
#  index_client_feed_requests_on_send_key    (account_id,user_id,request_id) UNIQUE
#
class ClientFeedRequest < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :message

  validates :request_id, presence: true, uniqueness: { scope: [:account_id, :user_id] }
end
