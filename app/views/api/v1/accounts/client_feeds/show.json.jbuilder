json.contact do
  json.partial! 'api/v1/models/contact', resource: @contact
end
json.conversations do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', conversation: conversation
  end
end
json.channels do
  json.array! @channels do |entry|
    inbox = entry[:inbox]
    json.id inbox.id
    json.name inbox.name
    json.platform inbox.channel.name
    json.online inbox.channel.online?
  end
end
json.default_conversation_id @default_conversation_id
