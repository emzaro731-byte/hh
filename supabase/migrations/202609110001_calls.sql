create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('audio','video')),
  status text not null default 'ringing' check (status in ('ringing','active','ended','rejected')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.calls(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('offer','answer','candidate')),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists calls_caller_idx on public.calls(caller_id, created_at desc);
create index if not exists calls_callee_idx on public.calls(callee_id, created_at desc);
create index if not exists call_signals_call_idx on public.call_signals(call_id, created_at asc);

alter table public.calls enable row level security;
alter table public.call_signals enable row level security;

drop policy if exists "call participants can read calls" on public.calls;
create policy "call participants can read calls" on public.calls for select using (auth.uid() = caller_id or auth.uid() = callee_id);

drop policy if exists "users can create calls" on public.calls;
create policy "users can create calls" on public.calls for insert with check (auth.uid() = caller_id);

drop policy if exists "call participants can update calls" on public.calls;
create policy "call participants can update calls" on public.calls for update using (auth.uid() = caller_id or auth.uid() = callee_id) with check (auth.uid() = caller_id or auth.uid() = callee_id);

drop policy if exists "call participants can read signals" on public.call_signals;
create policy "call participants can read signals" on public.call_signals for select using (exists (select 1 from public.calls c where c.id = call_id and (c.caller_id = auth.uid() or c.callee_id = auth.uid())));

drop policy if exists "call participants can create signals" on public.call_signals;
create policy "call participants can create signals" on public.call_signals for insert with check (auth.uid() = sender_id and exists (select 1 from public.calls c where c.id = call_id and (c.caller_id = auth.uid() or c.callee_id = auth.uid())));

alter table public.calls replica identity full;
alter table public.call_signals replica identity full;
alter publication supabase_realtime add table public.calls;
alter publication supabase_realtime add table public.call_signals;
