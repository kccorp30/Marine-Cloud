create table if not exists public.notification_preferences (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  sound_enabled boolean not null default true,
  motion_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_read_own on public.notification_preferences;
create policy notification_preferences_read_own
on public.notification_preferences for select
to authenticated
using (profile_id = auth.uid());

drop policy if exists notification_preferences_insert_own on public.notification_preferences;
create policy notification_preferences_insert_own
on public.notification_preferences for insert
to authenticated
with check (profile_id = auth.uid());

drop policy if exists notification_preferences_update_own on public.notification_preferences;
create policy notification_preferences_update_own
on public.notification_preferences for update
to authenticated
using (profile_id = auth.uid())
with check (profile_id = auth.uid());

revoke all on public.notification_preferences from anon;
grant select, insert, update on public.notification_preferences to authenticated;
