-- Ensure the message status columns used by the Flutter chat exist in the live database.
alter table public.messages
  add column if not exists delivered_at timestamptz,
  add column if not exists read_at timestamptz;

-- Ensure the existing attachment bucket is present for chat media uploads.
insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- Refresh PostgREST schema cache after the column changes.
notify pgrst, 'reload schema';
