<script setup>
import { computed, ref, watch } from 'vue';
import { useDocumentVisibility, useIntersectionObserver } from '@vueuse/core';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMapGetter } from 'dashboard/composables/store';
import { MESSAGE_VISIBILITY_THRESHOLD } from './constants';
import Message from 'dashboard/components-next/message/Message.vue';

const props = defineProps({
  message: { type: Object, required: true },
  reply: { type: Object, default: null },
  channel: { type: String, required: true },
  scrollRoot: { type: Object, default: null },
});
const emit = defineEmits(['seen', 'retry']);
const element = ref(null);
const visible = ref(false);
const visibility = useDocumentVisibility();
const user = useMapGetter('getCurrentUser');
const camelMessage = computed(() =>
  useCamelCase(props.message, { deep: true })
);
useIntersectionObserver(
  element,
  ([entry]) => {
    visible.value = entry.isIntersecting;
  },
  {
    root: computed(() => props.scrollRoot),
    threshold: MESSAGE_VISIBILITY_THRESHOLD,
  }
);
watch([visible, visibility], () => {
  if (visible.value && visibility.value === 'visible')
    emit('seen', props.message);
});
</script>

<template>
  <div ref="element" class="py-2">
    <p class="mb-2 text-xs text-n-slate-11">
      {{
        $t('CLIENT_FEED.MESSAGE_CONTEXT', {
          channel,
          id: message.conversation_id,
        })
      }}
    </p>
    <Message
      v-bind="camelMessage"
      :in-reply-to="reply ? useCamelCase(reply, { deep: true }) : null"
      :current-user-id="user.id"
      :inbox-supports-reply-to="{
        incoming: true,
        outgoing: !!message.source_id,
      }"
      @retry="emit('retry', message)"
    />
  </div>
</template>
