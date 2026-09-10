create table if not exists public.ai_generations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('chat','image','video','music')),
  prompt text not null,
  model text,
  task_id text,
  status text not null default 'completed',
  result_urls text[] not null default '{}',
  result_text text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists ai_generations_user_created_idx on public.ai_generations(user_id, created_at desc);

alter table public.ai_generations enable row level security;

drop policy if exists "users read own ai generations" on public.ai_generations;
drop policy if exists "users insert own ai generations" on public.ai_generations;
create policy "users read own ai generations" on public.ai_generations for select to authenticated using (user_id = auth.uid());
create policy "users insert own ai generations" on public.ai_generations for insert to authenticated with check (user_id = auth.uid());

insert into storage.buckets(id,name,public) values('ai-generations','ai-generations',false) on conflict(id) do nothing;
drop policy if exists "ai generations read own" on storage.objects;
drop policy if exists "ai generations upload own" on storage.objects;
create policy "ai generations read own" on storage.objects for select to authenticated using (bucket_id='ai-generations' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "ai generations upload own" on storage.objects for insert to authenticated with check (bucket_id='ai-generations' and (storage.foldername(name))[1]=auth.uid()::text);
