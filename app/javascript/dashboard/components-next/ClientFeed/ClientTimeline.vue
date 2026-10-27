<script setup>
import {
  computed,
  ref,
  onMounted,
  onBeforeUnmount,
  nextTick,
  provide,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useAlert } from 'dashboard/composables';
import { MESSAGE_ATTACHMENTS } from 'dashboard/components-next/message/provider';
import ClientFeedsAPI from 'dashboard/api/clientFeeds';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageAPI from 'dashboard/api/inbox/message';
import { emitter } from 'shared/helpers/mitt';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import ClientFeedMessage from './ClientFeedMessage.vue';
import ClientFeedComposer from './ClientFeedComposer.vue';
import { CLIENT_FEED_DEBOUNCE_MS, SCROLL_BOTTOM_THRESHOLD } from './constants';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
});
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const inboxGetter = useMapGetter('inboxes/getInbox');
const { run, isPending } = useAbortableRequest();
const historyRequest = useAbortableRequest();
const contact = ref(null);
const conversations = ref([]);
const channels = ref([]);
const messages = ref([]);
const hasMore = ref(false);
const selectedKey = ref('');
const quote = ref(null);
const scrollRoot = ref(null);
const failed = ref(false);
const changingStatus = ref(false);
const readWatermarks = new Map();
const deliveryUpdates = new Map();
let initialized = false;
let disposed = false;

provide(
  MESSAGE_ATTACHMENTS,
  computed(() => messages.value.flatMap(message => message.attachments || []))
);
const targets = computed(() => {
  const existing = conversations.value.map(conversation => {
    const inbox = inboxGetter.value(conversation.inbox_id);
    const channel = channels.value.find(
      item => item.id === conversation.inbox_id
    );
    const platform = channel?.platform || inbox.medium;
    return {
      key: `conversation-${conversation.id}`,
      conversationId: conversation.id,
      online: channel?.online ?? false,
      label: `${platform} · ${inbox.name} · #${conversation.id}`,
      conversation,
    };
  });
  const newChannels = channels.value
    .filter(
      channel =>
        !conversations.value.some(
          conversation => conversation.inbox_id === channel.id
        )
    )
    .map(channel => ({
      key: `inbox-${channel.id}`,
      inboxId: channel.id,
      online: channel.online,
      label: `${channel.platform} · ${channel.name}`,
    }));
  return [...existing, ...newChannels];
});
const selected = computed(() =>
  targets.value.find(target => target.key === selectedKey.value)
);
const mergeMessages = payload => {
  const allowed = new Set(
    conversations.value.map(conversation => conversation.id)
  );
  messages.value = [
    ...new Map(
      [...messages.value, ...payload]
        .filter(message => allowed.has(message.conversation_id))
        .map(message => [message.id, message])
    ).values(),
  ].sort((a, b) => a.created_at - b.created_at || a.id - b.id);
};
const nearBottom = () =>
  !scrollRoot.value ||
  scrollRoot.value.scrollHeight -
    scrollRoot.value.scrollTop -
    scrollRoot.value.clientHeight <
    SCROLL_BOTTOM_THRESHOLD;
const scrollToBottom = () =>
  nextTick(() => {
    if (scrollRoot.value)
      scrollRoot.value.scrollTop = scrollRoot.value.scrollHeight;
  });
const load = async (syncLatest = false) => {
  const stickToBottom = nearBottom();
  try {
    const response = await run(async signal => {
      const details = await ClientFeedsAPI.show(props.contactId, { signal });
      const allowed = new Set(
        details.data.conversations.map(conversation => conversation.id)
      );
      const current = messages.value.filter(message =>
        allowed.has(message.conversation_id)
      );
      const previous = new Set(
        conversations.value.map(conversation => conversation.id)
      );
      const resetHistory =
        !initialized ||
        previous.size !== allowed.size ||
        [...allowed].some(id => !previous.has(id));
      let after = resetHistory ? undefined : current.at(-1)?.id;
      const payload = [];
      let timeline;
      do {
        // Cursor pages depend on the preceding response.
        // eslint-disable-next-line no-await-in-loop
        const result = await ClientFeedsAPI.messages(props.contactId, {
          after,
          signal,
        });
        timeline = result.data;
        payload.push(...timeline.payload);
        if (!after || !timeline.has_more) break;
        after = timeline.payload.at(-1).id;
      } while (!signal.aborted);
      if (syncLatest && after) {
        const latest = await ClientFeedsAPI.messages(props.contactId, {
          signal,
        });
        payload.push(...latest.data.payload);
      }
      if (signal.aborted) return null;
      return {
        resetHistory,
        details: details.data,
        timeline: { payload, has_more: timeline.has_more },
      };
    });
    if (!response || disposed) return;
    const { details, timeline, resetHistory } = response;
    if (resetHistory) {
      messages.value = [];
      hasMore.value = timeline.has_more;
    }
    contact.value = details.contact;
    conversations.value = details.conversations;
    channels.value = details.channels;
    mergeMessages(timeline.payload);
    const updates = [...deliveryUpdates.values()].flatMap(update => {
      const existing = messages.value.find(message => message.id === update.id);
      return existing
        ? [{ ...existing, ...update, created_at: existing.created_at }]
        : [];
    });
    deliveryUpdates.clear();
    mergeMessages(updates);
    if (!initialized) {
      hasMore.value = timeline.has_more;
      if (details.default_conversation_id)
        selectedKey.value = `conversation-${details.default_conversation_id}`;
      initialized = true;
    }
    if (selectedKey.value && !selected.value) {
      selectedKey.value = '';
      quote.value = null;
    }
    failed.value = false;
    if (stickToBottom) scrollToBottom();
  } catch (error) {
    if ([401, 403, 404].includes(error.response?.status)) {
      conversations.value = [];
      channels.value = [];
      messages.value = [];
      selectedKey.value = '';
    }
    failed.value = true;
    useAlert(t('CLIENT_FEED.LOAD_ERROR'));
  }
};
const refresh = useDebounceFn(() => {
  if (!disposed) load();
}, CLIENT_FEED_DEBOUNCE_MS);
const onReconnect = () => load(true);
const onFeedUpdated = message => {
  if (message?.id) deliveryUpdates.set(message.id, message);
  refresh();
};
const loadOlder = async () => {
  const previousHeight = scrollRoot.value.scrollHeight;
  try {
    const response = await historyRequest.run(signal =>
      ClientFeedsAPI.messages(props.contactId, {
        before: messages.value[0]?.id,
        signal,
      })
    );
    if (!response || disposed) return;
    mergeMessages(response.data.payload);
    hasMore.value = response.data.has_more;
    nextTick(() => {
      if (!scrollRoot.value) return;
      scrollRoot.value.scrollTop +=
        scrollRoot.value.scrollHeight - previousHeight;
    });
  } catch {
    useAlert(t('CLIENT_FEED.LOAD_ERROR'));
  }
};
const flushRead = useDebounceFn(async () => {
  const shown = [...readWatermarks.entries()];
  readWatermarks.clear();
  const results = await Promise.allSettled(
    shown.map(([, message]) => ClientFeedsAPI.read(props.contactId, message.id))
  );
  if (results.some(result => result.status === 'rejected'))
    useAlert(t('CLIENT_FEED.READ_ERROR'));
}, CLIENT_FEED_DEBOUNCE_MS);
const onSeen = message => {
  const current = readWatermarks.get(message.conversation_id);
  if (
    !current ||
    message.created_at > current.created_at ||
    (message.created_at === current.created_at && message.id > current.id)
  ) {
    readWatermarks.set(message.conversation_id, message);
  }
  flushRead();
};
const onReplyTo = message => {
  if (!message) {
    quote.value = null;
    return;
  }
  const source = messages.value.find(item => item.id === message.id);
  if (!source || source.private || !source.source_id) return;
  LocalStorage.deleteFromJsonStore(
    LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO,
    source.conversation_id
  );
  selectedKey.value = `conversation-${source.conversation_id}`;
  quote.value = source;
};
const selectTarget = event => {
  selectedKey.value = event.target.value;
  quote.value = null;
};
const onSubmitted = async (message, originKey) => {
  const targetKey = `conversation-${message.conversation_id}`;
  if (selectedKey.value === originKey) selectedKey.value = targetKey;
  await load();
  if (!disposed) {
    if (!messages.value.some(item => item.id === message.id))
      mergeMessages([message]);
    if (selectedKey.value === targetKey) scrollToBottom();
  }
};

const retry = async message => {
  try {
    await MessageAPI.retry(message.conversation_id, message.id);
    refresh();
  } catch {
    useAlert(t('CONVERSATION.MESSAGE_ERROR'));
  }
};
const toggleStatus = async () => {
  const conversation = selected.value.conversation;
  changingStatus.value = true;
  try {
    await ConversationAPI.toggleStatus({
      conversationId: conversation.id,
      status: conversation.status === 'resolved' ? 'open' : 'resolved',
    });
    await load();
  } catch {
    useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
  } finally {
    changingStatus.value = false;
  }
};
const statusLabel = status =>
  ({
    open: t('CLIENT_FEED.STATUS.open'),
    resolved: t('CLIENT_FEED.STATUS.resolved'),
    pending: t('CLIENT_FEED.STATUS.pending'),
    snoozed: t('CLIENT_FEED.STATUS.snoozed'),
  })[status];
const channelLabel = message => {
  const inbox = inboxGetter.value(message.inbox_id);
  return `${channels.value.find(channel => channel.id === message.inbox_id)?.platform || inbox.medium} · ${inbox.name}`;
};
const quoteFor = message =>
  messages.value.find(
    item => item.id === message.content_attributes?.in_reply_to
  );
onMounted(() => {
  load();
  emitter.on(BUS_EVENTS.CLIENT_FEED_UPDATED, onFeedUpdated);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, onReconnect);
  emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, onReplyTo);
});
onBeforeUnmount(() => {
  disposed = true;
  emitter.off(BUS_EVENTS.CLIENT_FEED_UPDATED, onFeedUpdated);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, onReconnect);
  emitter.off(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, onReplyTo);
});
</script>

<template>
  <main class="flex min-w-0 flex-1 flex-col">
    <header
      class="flex flex-wrap items-center gap-3 border-b border-n-weak p-4"
    >
      <RouterLink
        :to="accountScopedRoute('client_feeds')"
        class="text-sm text-n-blue-text md:hidden"
      >
        {{ t('CLIENT_FEED.CLIENTS') }}
      </RouterLink>
      <h1 class="m-0 text-lg font-medium text-n-slate-12">
        {{ contact?.name || t('CLIENT_FEED.LOADING') }}
      </h1>
      <RouterLink
        v-if="contact"
        :to="accountScopedRoute('contacts_edit', { contactId: contact.id })"
        class="ms-auto text-sm text-n-blue-text"
      >
        {{ t('CLIENT_FEED.CONTACT_DETAILS') }}
      </RouterLink>
    </header>
    <div class="flex flex-col gap-2 border-b border-n-weak p-3">
      <label class="text-sm text-n-slate-11" for="client-feed-target">{{
        t('CLIENT_FEED.TARGET')
      }}</label>
      <select
        id="client-feed-target"
        :value="selectedKey"
        class="m-0 w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12"
        @change="selectTarget"
      >
        <option value="">{{ t('CLIENT_FEED.SELECT_CHANNEL') }}</option>
        <option v-for="target in targets" :key="target.key" :value="target.key">
          {{ target.label }}
          {{
            target.conversation
              ? `· ${statusLabel(target.conversation.status)} · ${target.conversation.meta.assignee?.name || t('CLIENT_FEED.UNASSIGNED')}`
              : ''
          }}
        </option>
      </select>
      <div
        v-if="selected?.conversation"
        class="flex flex-wrap items-center gap-3 text-sm text-n-slate-11"
      >
        <span>{{
          t('CLIENT_FEED.ACTION_TARGET', { id: selected.conversationId })
        }}</span>
        <Button
          size="sm"
          variant="ghost"
          :is-loading="changingStatus"
          :disabled="changingStatus"
          :label="
            selected.conversation.status === 'resolved'
              ? t('CLIENT_FEED.REOPEN')
              : t('CLIENT_FEED.RESOLVE')
          "
          @click="toggleStatus"
        />
        <RouterLink
          :to="
            accountScopedRoute('inbox_conversation', {
              conversation_id: selected.conversationId,
            })
          "
          class="text-n-blue-text"
        >
          {{ t('CLIENT_FEED.MANAGE_CONVERSATION') }}
        </RouterLink>
      </div>
    </div>
    <div
      ref="scrollRoot"
      class="min-h-0 flex-1 overflow-y-auto px-4"
      role="log"
      :aria-label="t('CLIENT_FEED.HISTORY')"
    >
      <Button
        v-if="hasMore"
        class="my-3"
        variant="ghost"
        :label="t('CLIENT_FEED.OLDER')"
        :is-loading="historyRequest.isPending.value"
        :disabled="historyRequest.isPending.value"
        @click="loadOlder"
      />
      <div v-if="failed" class="p-4 text-center text-n-ruby-9">
        <p>{{ t('CLIENT_FEED.LOAD_ERROR') }}</p>
        <Button
          :label="t('CLIENT_FEED.RETRY')"
          :is-loading="isPending"
          @click="load()"
        />
      </div>
      <p v-else-if="!messages.length" class="py-12 text-center text-n-slate-11">
        {{ isPending ? t('CLIENT_FEED.LOADING') : t('CLIENT_FEED.EMPTY') }}
      </p>
      <ClientFeedMessage
        v-for="message in messages"
        :key="message.id"
        :message="message"
        :reply="quoteFor(message)"
        :channel="channelLabel(message)"
        :scroll-root="scrollRoot"
        @seen="onSeen"
        @retry="retry"
      />
    </div>
    <ClientFeedComposer
      v-if="selected"
      :contact-id="contactId"
      :target="selected"
      :messages="messages"
      :quote="quote"
      @clear-quote="quote = null"
      @submitted="onSubmitted"
    />
    <p
      v-else-if="!isPending && !failed"
      class="m-0 border-t border-n-weak p-4 text-sm text-n-slate-11"
    >
      {{
        targets.length
          ? t('CLIENT_FEED.SELECT_CHANNEL')
          : t('CLIENT_FEED.NO_CHANNELS')
      }}
    </p>
  </main>
</template>
