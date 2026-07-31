-- Cover the conversation foreign key used by cascade deletes. The existing
-- viewer-first index remains the read path for a user's hidden messages.

create index if not exists message_hides_conversation_idx
  on public.message_hides (conversation_id);
