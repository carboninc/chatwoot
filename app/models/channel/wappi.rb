# == Schema Information
#
# Table name: channel_wappi
#
#  id                :bigint           not null, primary key
#  api_token         :text             not null
#  platform          :string           not null
#  provider_status   :string
#  status_checked_at :datetime
#  status_metadata   :jsonb            not null
#  status_reason     :string
#  webhook_secret    :text             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  profile_id        :string           not null
#
# Indexes
#
#  index_channel_wappi_on_account_id               (account_id)
#  index_channel_wappi_on_platform_and_profile_id  (platform,profile_id) UNIQUE
#
class Channel::Wappi < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wappi'

  PHONE_SOURCE_PREFIX = 'phone:'.freeze
  SUPPORTED_PLATFORMS = %w[whatsapp max].freeze
  PLATFORM_NAMES = { 'whatsapp' => 'WhatsApp', 'max' => 'MAX' }.freeze
  CREATION_ATTRS = [:platform, :profile_id, :api_token].freeze
  EDITABLE_ATTRS = [:api_token].freeze

  if Chatwoot.encryption_configured?
    encrypts :api_token
    encrypts :webhook_secret
  end

  before_validation :ensure_webhook_secret, on: :create
  after_destroy_commit :remove_provider_webhook

  validates :platform, inclusion: { in: SUPPORTED_PLATFORMS }
  validates :profile_id, presence: true, uniqueness: { scope: :platform }
  validates :api_token, :webhook_secret, presence: true

  def name
    PLATFORM_NAMES.fetch(platform)
  end

  def medium
    platform
  end

  def provider
    'wappi'
  end

  def source_id_for_phone(phone_number)
    digits = phone_number.gsub(/\D/, '')
    platform == 'max' ? "#{PHONE_SOURCE_PREFIX}#{digits}" : digits
  end

  def online?
    provider_status == 'online'
  end

  def webhook_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/wappi/#{platform}/#{profile_id}"
  end

  private

  def ensure_webhook_secret
    self.webhook_secret ||= SecureRandom.hex(32)
  end

  def remove_provider_webhook
    Wappi::WebhookTeardownService.new(self).perform
  rescue Wappi::Client::Error => e
    Rails.logger.warn("[WAPPI] Webhook teardown failed channel_id=#{id} error=#{e.class.name}")
  end
end
