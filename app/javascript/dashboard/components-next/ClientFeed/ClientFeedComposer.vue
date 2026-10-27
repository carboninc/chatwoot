<script setup>
import { computed, reactive, watch } from 'vue';
import { MESSAGE_MAX_LENGTH } from 'shared/helpers/MessageTypeHelper';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useClientFeedDrafts } from './useClientFeedDrafts';
import { useAlert } from 'dashboard/composables';
import ClientFeedsAPI from 'dashboard/api/clientFeeds';
import MessageAPI from 'dashboard/api/inbox/message';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
  target: { type: Object, required: true },
  messages: { type: Array, default: () => [] },
  quote: { type: Object, default: null },
});
const emit = defineEmits(['submitted', 'clearQuote']);
const store = useStore();
const { t } = useI18n();
const { accountId } = useAccount();
const drafts = useClientFeedDrafts();
const draftKey = computed(() => `${props.contactId}:${props.target.key}`);
const storageKey = key => `client-feed-${accountId.value}-${key}`;
watch(
  draftKey,
  key => {
    if (!drafts.has(key)) {
      drafts.set(
        key,
        reactive({
          content: store.getters['draftMessages/get'](storageKey(key)),
          files: [],
          submission: null,
          pendingMessageId: null,
          sending: false,
          failed: false,
          uncertain: false,
        })
      );
    }
  },
  { immediate: true }
);
const draft = computed(() => drafts.get(draftKey.value));
const locked = computed(
  () =>
    draft.value.sending ||
    draft.value.uncertain ||
    (draft.value.pendingMessageId && !draft.value.failed)
);
watch(
  () => draft.value.content,
  content => {
    store.dispatch('draftMessages/set', {
      key: storageKey(draftKey.value),
      message: content,
    });
  }
);
watch(
  () => props.messages,
  messages => {
    drafts.forEach((value, key) => {
      if (!value.pendingMessageId) return;
      const sent = messages.find(
        message => message.id === value.pendingMessageId
      );
      if (!sent) return;
      value.failed = sent.status === 'failed';
      if (
        !value.failed &&
        (sent.source_id || ['delivered', 'read'].includes(sent.status))
      ) {
        value.content = '';
        value.files = [];
        value.pendingMessageId = null;
        value.submission = null;
        value.uncertain = false;
        store.dispatch('draftMessages/delete', { key: storageKey(key) });
      }
    });
  },
  { deep: true, immediate: true }
);
const addFiles = event => {
  draft.value.files.push(...Array.from(event.target.files));
  event.target.value = '';
};
const submit = async () => {
  const value = draft.value;
  if (
    value.sending ||
    (value.pendingMessageId && !value.failed) ||
    !props.target.online ||
    (!value.content.trim() && !value.files.length)
  )
    return;
  const target = props.target;
  value.sending = true;
  value.submission ||= {
    content: value.content,
    files: [...value.files],
    requestId: crypto.randomUUID(),
    conversationId: target.conversationId,
    inboxId: target.inboxId,
    inReplyTo: props.quote?.id,
  };
  try {
    if (value.pendingMessageId) {
      await MessageAPI.retry(target.conversationId, value.pendingMessageId);
      value.failed = false;
    } else {
      const { data } = await ClientFeedsAPI.send(
        props.contactId,
        value.submission
      );
      if (target.inboxId) {
        drafts.set(
          `${props.contactId}:conversation-${data.conversation_id}`,
          value
        );
      }
      value.pendingMessageId = data.id;
      value.failed = data.status === 'failed';
      value.uncertain = false;
      emit('submitted', data, target.key);
      if (props.target.key === target.key) emit('clearQuote');
    }
  } catch (error) {
    value.failed = true;
    value.uncertain = !error.response || error.response.status >= 500;
    if (!value.uncertain && !value.pendingMessageId) value.submission = null;
    useAlert(error.response?.data?.error || t('CONVERSATION.MESSAGE_ERROR'));
  } finally {
    value.sending = false;
  }
};
</script>

<template>
  <form
    class="flex flex-col gap-3 border-t border-n-weak p-4"
    @submit.prevent="submit"
  >
    <div
      class="flex items-center justify-between gap-2 text-sm text-n-slate-11"
    >
      <span>{{ $t('CLIENT_FEED.REPLY_VIA', { channel: target.label }) }}</span>
      <span v-if="locked">{{ $t('CLIENT_FEED.SENDING') }}</span>
    </div>
    <div
      v-if="quote"
      class="flex items-center gap-2 rounded-lg bg-n-alpha-2 p-2 text-sm"
    >
      <span class="min-w-0 flex-1 truncate">
        {{ $t('CLIENT_FEED.QUOTING', { id: quote.id }) }}
        {{ quote.content }}
      </span>
      <Button
        type="button"
        icon="i-lucide-x"
        :aria-label="$t('CLIENT_FEED.CANCEL_QUOTE')"
        variant="ghost"
        :disabled="locked"
        @click="emit('clearQuote')"
      />
    </div>
    <TextArea
      v-model="draft.content"
      :max-length="MESSAGE_MAX_LENGTH.GENERAL"
      :placeholder="$t('CLIENT_FEED.WRITE_REPLY')"
      :disabled="!!locked || !!draft.pendingMessageId"
    />
    <ul
      v-if="draft.files.length"
      class="m-0 flex list-none flex-wrap gap-2 p-0"
    >
      <li
        v-for="(file, index) in draft.files"
        :key="index"
        class="flex items-center gap-1 rounded-lg bg-n-alpha-2 px-2 text-sm"
      >
        {{ file.name }}
        <Button
          type="button"
          icon="i-lucide-x"
          :aria-label="$t('CLIENT_FEED.REMOVE_ATTACHMENT')"
          variant="ghost"
          :disabled="!!locked || !!draft.pendingMessageId"
          @click="draft.files.splice(index, 1)"
        />
      </li>
    </ul>
    <p v-if="!target.online" class="mb-0 text-sm text-n-ruby-9">
      {{ $t('CLIENT_FEED.OFFLINE') }}
    </p>
    <p v-if="draft.failed" role="alert" class="mb-0 text-sm text-n-ruby-9">
      {{ $t('CLIENT_FEED.SEND_ERROR') }}
    </p>
    <div class="flex items-center justify-between gap-2">
      <label class="cursor-pointer text-sm text-n-slate-11">
        {{ $t('CLIENT_FEED.ATTACH') }}
        <input
          type="file"
          multiple
          class="sr-only"
          :disabled="!!locked || !!draft.pendingMessageId"
          @change="addFiles"
        />
      </label>
      <Button
        type="submit"
        :label="
          draft.failed
            ? $t('CLIENT_FEED.RETRY')
            : $t('CONVERSATION.REPLYBOX.SEND')
        "
        :is-loading="draft.sending"
        :disabled="
          draft.sending ||
          (!draft.failed && !!locked) ||
          !target.online ||
          (!draft.content.trim() && !draft.files.length)
        "
      />
    </div>
  </form>
</template>
