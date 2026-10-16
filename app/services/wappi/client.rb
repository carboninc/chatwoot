class Wappi::Client
  BASE_URL = 'https://wappi.pro'.freeze
  PLATFORM_PREFIXES = { 'whatsapp' => 'api' }.freeze
  REQUEST_TIMEOUT = 20

  class Error < StandardError; end

  class ApiError < Error
    attr_reader :http_status

    def initialize(message, http_status: nil)
      @http_status = http_status
      super(message)
    end
  end

  class AuthenticationError < ApiError; end
  class NetworkError < Error; end

  def initialize(profile_id:, api_token:, platform:)
    @profile_id = profile_id
    @api_token = api_token
    @prefix = PLATFORM_PREFIXES.fetch(platform)
  end

  def status
    get('/sync/get/status')
  end

  def set_webhook(url:, secret:)
    post('/webhook/url/set', query: { url: url, auth: secret })
  end

  def configure_webhook_types(types)
    post('/webhook/types/set', body: types)
  end

  def delete_webhook
    post('/webhook/url/delete')
  end

  def send_text(recipient:, body:, bot_id:)
    post('/sync/message/send', query: { bot_id: bot_id }, body: recipient_payload(recipient).merge(body: body))
  end

  def send_file(recipient:, url:, caption:, file_name:, bot_id:)
    body = recipient_payload(recipient).merge(url: url, caption: caption, file_name: file_name).compact
    post('/sync/message/file/url/send', query: { bot_id: bot_id }, body: body)
  end

  def reply(message_id:, body:, bot_id:, url: nil)
    post('/sync/message/reply', query: { bot_id: bot_id }, body: { message_id: message_id, body: body, url: url }.compact)
  end

  private

  def recipient_payload(recipient)
    recipient.to_s.end_with?('@lid') ? { chat_id: recipient } : { recipient: recipient }
  end

  def get(path, query: {})
    request(:get, path, query: query)
  end

  def post(path, query: {}, body: nil)
    request(:post, path, query: query, body: body)
  end

  def request(method, path, query:, body: nil)
    response = HTTParty.public_send(
      method,
      "#{BASE_URL}/#{@prefix}#{path}",
      headers: { 'Authorization' => @api_token, 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
      query: { profile_id: @profile_id }.merge(query),
      body: body&.to_json,
      timeout: REQUEST_TIMEOUT
    )

    parse_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, EOFError,
         Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    raise NetworkError, "Wappi network error for #{path}: #{e.class.name}"
  end

  def parse_response(response)
    payload = response.parsed_response
    payload = JSON.parse(response.body) unless payload.is_a?(Hash)

    return payload if response.success? && payload['status'] != 'error'

    raise error_class(response).new(error_message(response, payload), http_status: response.code)
  rescue JSON::ParserError, TypeError
    raise ApiError.new('Wappi returned an invalid response', http_status: response.code)
  end

  def error_class(response)
    [401, 403].include?(response.code) ? AuthenticationError : ApiError
  end

  def error_message(response, payload)
    payload['detail'].presence || payload['message'].presence || "Wappi API error (HTTP #{response.code})"
  end
end
