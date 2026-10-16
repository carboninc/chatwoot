<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const inboxName = ref('');
const profileId = ref('');
const apiToken = ref('');

const router = useRouter();
const store = useStore();
const { t } = useI18n();
const uiFlags = useMapGetter('inboxes/getUIFlags');

const rules = {
  inboxName: { required },
  profileId: { required },
  apiToken: { required },
};
const v$ = useVuelidate(rules, { inboxName, profileId, apiToken });

const errorMessage = error => {
  const parsedError = parseAPIErrorResponse(error);
  return typeof parsedError === 'string'
    ? parsedError
    : t('INBOX_MGMT.ADD.WAPPI_CHANNEL.API.ERROR_MESSAGE');
};

const createChannel = async () => {
  const valid = await v$.value.$validate();
  if (!valid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim(),
      channel: {
        type: 'wappi',
        platform: 'whatsapp',
        profile_id: profileId.value.trim(),
        api_token: apiToken.value.trim(),
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (error) {
    useAlert(errorMessage(error));
  }
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.WAPPI_CHANNEL.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.WAPPI_CHANNEL.DESC')"
    />
    <form class="flex flex-col gap-4" @submit.prevent="createChannel">
      <label class="flex flex-col gap-1">
        <span>{{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.INBOX_NAME.LABEL') }}</span>
        <input
          v-model="inboxName"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.INBOX_NAME.PLACEHOLDER')
          "
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="text-sm text-n-ruby-11">
          {{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.REQUIRED') }}
        </span>
      </label>

      <label class="flex flex-col gap-1">
        <span>{{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.PROFILE_ID.LABEL') }}</span>
        <input
          v-model="profileId"
          type="text"
          autocomplete="off"
          :placeholder="
            $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.PROFILE_ID.PLACEHOLDER')
          "
          @blur="v$.profileId.$touch"
        />
        <span class="text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.PROFILE_ID.HELP') }}
        </span>
        <span v-if="v$.profileId.$error" class="text-sm text-n-ruby-11">
          {{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.REQUIRED') }}
        </span>
      </label>

      <label class="flex flex-col gap-1">
        <span>{{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.API_TOKEN.LABEL') }}</span>
        <input
          v-model="apiToken"
          type="password"
          autocomplete="new-password"
          :placeholder="
            $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.API_TOKEN.PLACEHOLDER')
          "
          @blur="v$.apiToken.$touch"
        />
        <span v-if="v$.apiToken.$error" class="text-sm text-n-ruby-11">
          {{ $t('INBOX_MGMT.ADD.WAPPI_CHANNEL.REQUIRED') }}
        </span>
      </label>

      <div class="mt-2">
        <NextButton
          type="submit"
          solid
          blue
          :is-loading="uiFlags.isCreating"
          :label="$t('INBOX_MGMT.ADD.WAPPI_CHANNEL.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
