class Wappi::DeliveryStatusService
  STATUS_MAPPING = {
    'pending' => 'sent',
    'delivered' => 'delivered',
    'read' => 'read',
    'undelivered' => 'failed',
    'temporary ban' => 'failed',
    'error' => 'failed'
  }.freeze

  def initialize(inbox:, event:)
    @inbox = inbox
    @event = event.with_indifferent_access
  end

  def perform
    status = STATUS_MAPPING[@event[:status]]
    return if status.blank? || message.blank?

    error = @event[:detail].presence || @event[:reason].presence if status == 'failed'
    Messages::StatusUpdateService.new(message, status, error).perform
  end

  private

  def message
    @message ||= begin
      found = @inbox.messages.find_by(source_id: @event[:id])
      found ||= find_by_external_id('wappi_message_ids', @event[:id])
      found ||= find_by_external_id('wappi_task_ids', @event[:task_id])
      found
    end
  end

  def find_by_external_id(key, value)
    return if value.blank?

    # Message.store serializes the JSONB value as JSON text.
    @inbox.messages.where("(external_source_ids #>> '{}')::jsonb @> ?", { key => [value] }.to_json).first
  end
end
