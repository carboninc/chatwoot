import { nextTick } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export const RELOAD_DRAFT_KEYS = {
  CONVERSATION: 'cw-reload-conversation-draft',
  CLIENT_FEED: 'cw-reload-client-feed-draft',
};

export const rememberReloadDraft = (key, draft) => {
  window.sessionStorage.setItem(key, JSON.stringify(draft));
};

export const takeReloadDraft = key => {
  const value = window.sessionStorage.getItem(key);
  window.sessionStorage.removeItem(key);
  return JSON.parse(value);
};

export const reloadWithDrafts = async () => {
  // Flush v-model/watch updates before asking mounted editors to save.
  await nextTick();
  const request = { blocked: false, draftSaves: [], beforeReload: [] };
  emitter.emit(BUS_EVENTS.BEFORE_APP_RELOAD, request);
  await Promise.all(request.draftSaves);
  if (request.blocked) return false;

  request.beforeReload.forEach(prepare => prepare());
  window.location.reload();
  return true;
};
