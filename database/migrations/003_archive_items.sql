-- Suggested migration, reviewed against 001/002. Apply once after both.
-- No change to public message columns or anonymous write permissions.
begin;
create table public.archive_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('memory','event','favorite','progress')),
  item_id text not null check (char_length(item_id) between 1 and 200),
  payload jsonb not null default '{}' check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 8192),
  primary key (user_id,kind,item_id)
);
alter table public.archive_items enable row level security;
revoke all on public.archive_items from anon, authenticated;
grant select, insert, update, delete on public.archive_items to authenticated;
create policy "Read own archive" on public.archive_items for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own archive" on public.archive_items for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own archive" on public.archive_items for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own archive" on public.archive_items for delete to authenticated using ((select auth.uid()) = user_id);
-- Owner status is returned by a constrained authenticated function; sender UUID stays private.
create policy "Read own submitted messages" on public.fan_messages for select to authenticated using ((select auth.uid()) = user_id);
create function public.my_archive_messages()
returns table (id uuid, kind text, name text, country text, body text, spectrum text, status text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.id,m.kind,m.name,m.country,m.body,m.spectrum,m.status,m.created_at
  from public.fan_messages m where m.user_id = (select auth.uid())
  order by m.created_at desc limit 100;
$$;
revoke all on function public.my_archive_messages() from public, anon;
grant execute on function public.my_archive_messages() to authenticated;
commit;

