<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const route = useRoute();
const { accountScopedRoute } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const available = computed(() =>
  inboxes.value.some(inbox => inbox.channel_type === 'Channel::Wappi')
);
const clientsActive = computed(() => route.name === 'client_feeds');
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <nav
    v-if="available"
    class="flex gap-1 border-b border-n-weak p-3"
    :aria-label="$t('CLIENT_FEED.MODE')"
  >
    <RouterLink
      :to="accountScopedRoute('home')"
      class="flex-1 rounded-lg px-3 py-2 text-center text-sm"
      :class="
        !clientsActive ? 'bg-n-alpha-2 text-n-slate-12' : 'text-n-slate-11'
      "
    >
      {{ $t('CLIENT_FEED.CONVERSATIONS') }}
    </RouterLink>
    <RouterLink
      :to="accountScopedRoute('client_feeds')"
      class="flex-1 rounded-lg px-3 py-2 text-center text-sm"
      :class="
        clientsActive ? 'bg-n-alpha-2 text-n-slate-12' : 'text-n-slate-11'
      "
    >
      {{ $t('CLIENT_FEED.CLIENTS') }}
    </RouterLink>
  </nav>
</template>
