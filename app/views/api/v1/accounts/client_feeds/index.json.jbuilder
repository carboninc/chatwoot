json.payload do
  json.array! @contacts do |contact|
    json.partial! 'api/v1/models/contact', resource: contact
  end
end
json.has_more @contacts.next_page.present?
