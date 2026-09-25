-- Chạy sau 001. Bài mới chờ duyệt; quản trị duyệt trong Supabase Dashboard.
begin;
create table public.fan_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('star','note')),
  name text not null check (char_length(btrim(name)) between 2 and 50),
  country text not null check (char_length(btrim(country)) between 1 and 60),
  body text not null check (char_length(btrim(body)) between 1 and 200),
  spectrum text not null check (spectrum in ('junior','mark','jummo')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
alter table public.fan_messages enable row level security;
revoke all on public.fan_messages from anon, authenticated;
grant select (id,kind,name,country,body,spectrum,created_at,status) on public.fan_messages to anon, authenticated;
grant insert (user_id,kind,name,country,body,spectrum) on public.fan_messages to authenticated;
create policy "Read approved messages" on public.fan_messages for select to anon, authenticated using (status='approved');
create policy "Submit own pending message" on public.fan_messages for insert to authenticated with check ((select auth.uid())=user_id and status='pending');
create index fan_messages_public_feed on public.fan_messages (kind,created_at desc) where status='approved';
commit;
