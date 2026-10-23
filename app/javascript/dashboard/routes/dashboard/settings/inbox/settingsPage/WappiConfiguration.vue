<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { WAPPI_PLATFORM_NAMES } from 'dashboard/helper/inbox';
import { useStore } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import InboxHealthAPI from 'dashboard/api/inboxHealth';

import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();
const apiToken = ref('');
const health = ref(null);
const isChecking = ref(false);
const isUpdating = ref(false);
const isRegistering = ref(false);

const currentStatus = computed(
  () => health.value?.status || props.inbox.provider_status || 'unknown'
);
const statusReason = computed(
  () => health.value?.reason || props.inbox.status_reason || ''
);
const statusClasses = computed(() =>
  currentStatus.value === 'online'
    ? 'bg-n-teal-3 text-n-teal-11'
    : 'bg-n-ruby-3 text-n-ruby-11'
);

const errorMessage = error => {
  const parsedError = parseAPIErrorResponse(error);
  return typeof parsedError === 'string'
    ? parsedError
    : t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.ERROR_MESSAGE');
};

const checkConnection = async () => {
  isChecking.value = true;
  try {
    const response = await InboxHealthAPI.getHealthStatus(props.inbox.id);
    health.value = response.data;
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.CHECK_SUCCESS'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isChecking.value = false;
  }
};

const registerWebhook = async () => {
  isRegistering.value = true;
  try {
    await InboxHealthAPI.registerWebhook(props.inbox.id);
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.RECONNECT_SUCCESS'));
    await checkConnection();
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isRegistering.value = false;
  }
};

const updateToken = async () => {
  if (!apiToken.value.trim()) return;

  isUpdating.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: { api_token: apiToken.value.trim() },
    });
    apiToken.value = '';
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.TOKEN_SUCCESS'));
    await checkConnection();
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <div>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.PROVIDER')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.PROVIDER_HELP')"
    >
      <p class="text-body-main text-n-slate-12">
        {{
          $t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.PROVIDER_NAME', {
            platform: WAPPI_PLATFORM_NAMES[inbox.platform],
          })
        }}
      </p>
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.PROFILE_ID')"
    >
      <woot-code :script="inbox.profile_id" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.STATUS')"
      :help-text="statusReason"
    >
      <div class="flex flex-wrap items-center gap-3">
        <span
          class="rounded-full px-3 py-1 text-sm font-medium"
          :class="statusClasses"
        >
          {{ currentStatus }}
        </span>
        <NextButton
          :is-loading="isChecking"
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.CHECK')"
          @click="checkConnection"
        />
        <NextButton
          :is-loading="isRegistering"
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.RECONNECT')"
          @click="registerWebhook"
        />
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.UPDATE_TOKEN')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.UPDATE_TOKEN_HELP')"
    >
      <div class="flex items-center gap-2">
        <input
          v-model="apiToken"
          type="password"
          autocomplete="new-password"
          class="mb-0 flex-1"
          :placeholder="$t('INBOX_MGMT.SETTINGS_POPUP.WAPPI.TOKEN_PLACEHOLDER')"
        />
        <NextButton
          :disabled="!apiToken.trim()"
          :is-loading="isUpdating"
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
          @click="updateToken"
        />
      </div>
    </SettingsFieldSection>
  </div>
</template>
