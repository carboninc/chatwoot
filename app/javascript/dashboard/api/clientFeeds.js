/* global axios */
import ApiClient from './ApiClient';

class ClientFeedsAPI extends ApiClient {
  constructor() {
    super('client_feeds', { accountScoped: true });
  }

  get({ page = 1, q = '', signal } = {}) {
    return axios.get(this.url, { params: { page, q }, signal });
  }

  show(contactId, { signal } = {}) {
    return axios.get(`${this.url}/${contactId}`, { signal });
  }

  messages(contactId, { before, after, signal } = {}) {
    return axios.get(`${this.url}/${contactId}/messages`, {
      params: { before, after },
      signal,
    });
  }

  send(
    contactId,
    { content, files, requestId, conversationId, inboxId, inReplyTo }
  ) {
    const data = new FormData();
    data.append('content', content);
    data.append('request_id', requestId);
    if (conversationId) data.append('conversation_id', conversationId);
    if (inboxId) data.append('inbox_id', inboxId);
    if (inReplyTo) data.append('in_reply_to', inReplyTo);
    files.forEach(file => data.append('attachments[]', file));
    return axios.post(`${this.url}/${contactId}/messages`, data);
  }

  read(contactId, messageId) {
    return axios.post(`${this.url}/${contactId}/read`, {
      message_id: messageId,
    });
  }
}

export default new ClientFeedsAPI();
