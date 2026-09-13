-- Ensure GG chat attachments are available in the deployed Supabase project.
insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- Authenticated users can read chat attachments through signed URLs.
create policy if not exists "gg chat media read"
on storage.objects for select to authenticated
using (bucket_id = 'chat-media');

-- Users may upload files into their own user folder.
create policy if not exists "gg chat media upload"
on storage.objects for insert to authenticated
with check (bucket_id = 'chat-media' and owner_id = auth.uid()::text);

-- Users may delete only their own chat attachments.
create policy if not exists "gg chat media delete own"
on storage.objects for delete to authenticated
using (bucket_id = 'chat-media' and owner_id = auth.uid()::text);
