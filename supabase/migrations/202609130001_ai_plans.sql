-- GG AI plan state. Free is the default; paid plans are managed server-side.
alter table public.profiles
  add column if not exists ai_plan text not null default 'free';

alter table public.profiles
  drop constraint if exists profiles_ai_plan_check;

alter table public.profiles
  add constraint profiles_ai_plan_check
  check (ai_plan in ('free','go','plus','ultra'));

-- Users may edit their profile, but must never be able to promote themselves.
create or replace function public.prevent_client_ai_plan_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and new.ai_plan is distinct from old.ai_plan then
    raise exception 'AI plan can only be changed by the server';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_prevent_ai_plan_change on public.profiles;
create trigger profiles_prevent_ai_plan_change
before update on public.profiles
for each row execute function public.prevent_client_ai_plan_change();

create index if not exists profiles_ai_plan_idx on public.profiles(ai_plan);
