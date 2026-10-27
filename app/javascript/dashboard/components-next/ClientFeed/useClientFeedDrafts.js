import { inject, provide, reactive } from 'vue';

const CLIENT_FEED_DRAFTS = Symbol('ClientFeedDrafts');

export const provideClientFeedDrafts = () => {
  const drafts = reactive(new Map());
  provide(CLIENT_FEED_DRAFTS, drafts);
  return drafts;
};

export const useClientFeedDrafts = () => inject(CLIENT_FEED_DRAFTS);
