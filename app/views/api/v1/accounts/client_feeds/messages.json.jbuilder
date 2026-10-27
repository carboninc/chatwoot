json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/accounts/client_feeds/message', message: message
  end
end
json.has_more @has_more
