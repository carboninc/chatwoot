<script setup>
import { computed } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { reloadWithDrafts } from 'dashboard/helper/appReload';
import Banner from 'dashboard/components-next/banner/Banner.vue';

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const globalConfig = useMapGetter('globalConfig/get');
const store = useStore();
const updateAvailable = computed(() => {
  const loadedSha = globalConfig.value.gitSha;
  const releaseSha = currentAccount.value.release_sha;
  return (
    loadedSha &&
    releaseSha &&
    loadedSha !== 'unknown' &&
    releaseSha !== 'unknown' &&
    loadedSha !== releaseSha
  );
});
const checkRelease = () => {
  if (accountId.value && document.visibilityState === 'visible') {
    store.dispatch('accounts/get', { silent: true });
  }
};
useEventListener(window, 'focus', checkRelease);
useEventListener(document, 'visibilitychange', checkRelease);

const refresh = async () => {
  try {
    if (!(await reloadWithDrafts())) useAlert(t('RELEASE_UPDATE.FINISH_REPLY'));
  } catch {
    useAlert(t('RELEASE_UPDATE.SAVE_FAILED'));
  }
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Banner
    v-if="updateAvailable"
    color="blue"
    class="shrink-0 rounded-none border-x-0 border-t-0"
    role="status"
    :action-label="t('RELEASE_UPDATE.REFRESH')"
    @action="refresh"
  >
    {{ t('RELEASE_UPDATE.AVAILABLE') }}
  </Banner>
</template>
