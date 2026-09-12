-- GG Messenger: Status + social comments
create table if not exists public.statuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null default 'text' check (type in ('text','image','video')),
  text text,
  media_url text,
  background text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);
create index if not exists statuses_user_expires_idx on public.statuses(user_id, expires_at desc);
create index if not exists statuses_expires_idx on public.statuses(expires_at);

create table if not exists public.status_views (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key(status_id, viewer_id)
);
create table if not exists public.status_reactions (
  status_id uuid not null references public.statuses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null default '❤️',
  created_at timestamptz not null default now(),
  primary key(status_id, user_id)
);
create table if not exists public.status_replies (
  id uuid primary key default gen_random_uuid(),
  status_id uuid not null references public.statuses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

-- Generic comments can be attached to future GG social posts/content.
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  content_id uuid not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists comments_content_created_idx on public.comments(content_id, created_at);
create index if not exists comments_parent_idx on public.comments(parent_id);

alter table public.statuses enable row level security;
alter table public.status_views enable row level security;
alter table public.status_reactions enable row level security;
alter table public.status_replies enable row level security;
alter table public.comments enable row level security;

create policy "active statuses readable" on public.statuses for select to authenticated using (expires_at > now());
create policy "users create own statuses" on public.statuses for insert to authenticated with check (user_id = auth.uid());
create policy "users update own statuses" on public.statuses for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users delete own statuses" on public.statuses for delete to authenticated using (user_id = auth.uid());
create policy "users record status views" on public.status_views for insert to authenticated with check (viewer_id = auth.uid());
create policy "users read status views" on public.status_views for select to authenticated using (viewer_id = auth.uid() or exists(select 1 from public.statuses s where s.id=status_id and s.user_id=auth.uid()));
create policy "users manage own reactions" on public.status_reactions for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "users read status reactions" on public.status_reactions for select to authenticated using (true);
create policy "users create status replies" on public.status_replies for insert to authenticated with check (user_id=auth.uid());
create policy "users read status replies" on public.status_replies for select to authenticated using (true);
create policy "users delete own status replies" on public.status_replies for delete to authenticated using (user_id=auth.uid());
create policy "users read comments" on public.comments for select to authenticated using (true);
create policy "users create comments" on public.comments for insert to authenticated with check (author_id=auth.uid());
create policy "users update own comments" on public.comments for update to authenticated using (author_id=auth.uid()) with check (author_id=auth.uid());
create policy "users delete own comments" on public.comments for delete to authenticated using (author_id=auth.uid());

insert into storage.buckets(id,name,public) values('status-media','status-media',false) on conflict(id) do nothing;
create policy "status media read" on storage.objects for select to authenticated using (bucket_id='status-media');
create policy "status media upload" on storage.objects for insert to authenticated with check (bucket_id='status-media' and owner_id=auth.uid()::text);
create policy "status media delete own" on storage.objects for delete to authenticated using (bucket_id='status-media' and owner_id=auth.uid()::text);

alter publication supabase_realtime add table public.statuses;
alter publication supabase_realtime add table public.status_views;
alter publication supabase_realtime add table public.status_reactions;
alter publication supabase_realtime add table public.status_replies;
