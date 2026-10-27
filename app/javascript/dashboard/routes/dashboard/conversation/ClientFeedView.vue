<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { CLIENT_FEED_DEBOUNCE_MS } from 'dashboard/components-next/ClientFeed/constants';
import ClientFeedsAPI from 'dashboard/api/clientFeeds';
import FeedModeSwitch from 'dashboard/components-next/ClientFeed/FeedModeSwitch.vue';
import { provideClientFeedDrafts } from 'dashboard/components-next/ClientFeed/useClientFeedDrafts';
import ClientTimeline from 'dashboard/components-next/ClientFeed/ClientTimeline.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const { run, isPending } = useAbortableRequest();
const contacts = ref([]);
const query = ref('');
const page = ref(1);
const hasMore = ref(false);
const failed = ref(false);
// Keep files and pending sends when switching between clients in this view.
const drafts = provideClientFeedDrafts();

const load = async (append = false) => {
  const nextPage = append ? page.value + 1 : 1;
  try {
    failed.value = false;
    const response = await run(signal =>
      ClientFeedsAPI.get({ page: nextPage, q: query.value, signal })
    );
    if (!response) return;
    contacts.value = append
      ? [
          ...new Map(
            [...contacts.value, ...response.data.payload].map(contact => [
              contact.id,
              contact,
            ])
          ).values(),
        ]
      : response.data.payload;
    page.value = nextPage;
    hasMore.value = response.data.has_more;
  } catch {
    failed.value = true;
    useAlert(t('CLIENT_FEED.LOAD_ERROR'));
  }
};
let disposed = false;
const refresh = useDebounceFn(() => {
  if (!disposed) load();
}, CLIENT_FEED_DEBOUNCE_MS);
watch(
  () => route.params.accountId,
  () => {
    drafts.clear();
    contacts.value = [];
    load();
  }
);
watch(query, refresh);
onMounted(() => {
  store.dispatch('clearSelectedState');
  store.dispatch('inboxes/get');
  load();
  emitter.on(BUS_EVENTS.CLIENT_FEED_UPDATED, refresh);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, refresh);
});
onBeforeUnmount(() => {
  disposed = true;
  emitter.off(BUS_EVENTS.CLIENT_FEED_UPDATED, refresh);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, refresh);
});
</script>

<template>
  <section class="flex h-full w-full min-w-0 bg-n-surface-1">
    <aside
      class="flex w-full shrink-0 flex-col border-e border-n-weak md:w-80"
      :class="{ 'hidden md:flex': route.params.contactId }"
    >
      <FeedModeSwitch />
      <div class="p-3">
        <Input
          v-model="query"
          type="search"
          :placeholder="t('CLIENT_FEED.SEARCH')"
          :aria-label="t('CLIENT_FEED.SEARCH')"
        />
      </div>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <RouterLink
          v-for="contact in contacts"
          :key="contact.id"
          :to="accountScopedRoute('client_feeds', { contactId: contact.id })"
          class="block border-b border-n-weak px-4 py-3 hover:bg-n-alpha-1"
          :class="{
            'bg-n-alpha-2': Number(route.params.contactId) === contact.id,
          }"
        >
          <p class="mb-1 truncate font-medium text-n-slate-12">
            {{ contact.name }}
          </p>
          <p class="mb-0 truncate text-sm text-n-slate-11">
            {{ contact.phone_number || contact.email }}
          </p>
        </RouterLink>
        <p
          v-if="!contacts.length && !isPending"
          class="p-4 text-sm text-n-slate-11"
        >
          {{ t('CLIENT_FEED.NO_CLIENTS') }}
        </p>
        <Button
          v-if="hasMore || failed"
          class="m-3"
          variant="ghost"
          :label="failed ? t('CLIENT_FEED.RETRY') : t('CLIENT_FEED.MORE')"
          :is-loading="isPending"
          @click="load(!failed)"
        />
        <p v-else-if="isPending" class="p-4 text-sm text-n-slate-11">
          {{ t('CLIENT_FEED.LOADING') }}
        </p>
      </div>
    </aside>
    <ClientTimeline
      v-if="route.params.contactId"
      :key="`${route.params.accountId}:${route.params.contactId}`"
      :contact-id="Number(route.params.contactId)"
    />
    <div
      v-else
      class="hidden flex-1 items-center justify-center text-n-slate-11 md:flex"
    >
      {{ t('CLIENT_FEED.SELECT_CLIENT') }}
    </div>
  </section>
</template>
