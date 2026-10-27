import { inject, provide, reactive } from 'vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const CLIENT_FEED_DRAFTS = Symbol('ClientFeedDrafts');

export const provideClientFeedDrafts = () => {
  const drafts = reactive(new Map());
  const { accountId } = useAccount();
  const store = useStore();
  useEmitter(BUS_EVENTS.BEFORE_APP_RELOAD, request => {
    drafts.forEach((draft, key) => {
      request.draftSaves.push(
        store.dispatch('draftMessages/set', {
          key: `client-feed-${accountId.value}-${key}`,
          message: draft.content,
        })
      );
      request.blocked ||= !!(
        draft.files.length ||
        draft.submission ||
        draft.sending ||
        draft.pendingMessageId
      );
    });
  });
  provide(CLIENT_FEED_DRAFTS, drafts);
  return drafts;
};

export const useClientFeedDrafts = () => inject(CLIENT_FEED_DRAFTS);
