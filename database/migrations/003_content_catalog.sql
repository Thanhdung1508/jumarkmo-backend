-- Chạy sau 001 và 002. Nội dung published mới được đọc công khai.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;
create table private.staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','editor','moderator'))
);
revoke all on private.staff from public,anon,authenticated;
create function private.has_role(required_role text) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from private.staff where user_id=(select auth.uid()) and role in ('admin',required_role));
$$;
revoke all on function private.has_role(text) from public;
grant execute on function private.has_role(text) to anon,authenticated;

-- Cho phép asset nội bộ hoặc HTTPS; cấm javascript:, data: và URL //host.
create domain public.asset_url as text check (value ~ '^/[^/]' or value ~ '^https://[^[:space:]]+$');
create domain public.publish_state as text check(value in ('draft','published','archived'));
create table public.artists (
 id text primary key check(id ~ '^[a-z][a-z0-9-]{0,59}$'), name text not null,
 kind text not null check(kind in ('artist','mascot')), birthday date,
 stage_image public.asset_url not null, portrait_image public.asset_url not null,
 label text not null, color_label text not null, role_label text not null,
 bio text not null default '', stage_description text not null default '', skills text[] not null default '{}',
 source_url public.asset_url, sort_order int not null default 0,
 status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.works (
 id text primary key, title text not null, era_label text not null, year_label text not null,
 kind text not null check(kind in ('series','film','fancon','other')),
 description text not null default '', image public.asset_url not null,
 source_url public.asset_url, sort_order int not null default 0,
 status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.work_roles (
 work_id text references public.works(id) on delete cascade,
 artist_id text references public.artists(id) on delete cascade, role_name text not null,
 primary key(work_id,artist_id)
);
create table public.media_items (
 id text primary key, title text not null, alt text not null, kind text not null default 'photo' check(kind in ('photo','video')),
 url public.asset_url not null, thumbnail_url public.asset_url, file_name text not null,
 credit text not null, source_url public.asset_url, topic text not null default 'cozy', tag text not null default '',
 captured_at date, position text not null default 'center', downloadable boolean not null default false,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.media_artists (
 media_id text references public.media_items(id) on delete cascade,
 artist_id text references public.artists(id) on delete cascade, primary key(media_id,artist_id)
);
create table public.tracks (
 id text primary key, title text not null, subtitle text not null default '',
 audio_url public.asset_url, artist_id text references public.artists(id), work_id text references public.works(id),
 kind text not null default 'playlist' check(kind in ('playlist','ost','voice_memo')),
 source_url public.asset_url, sort_order int not null default 0,
 status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.events (
 id text primary key, title text not null, description text not null default '',
 starts_at timestamptz not null, ends_at timestamptz, timezone text not null default 'Asia/Bangkok',
 all_day boolean not null default false, category text not null check(category in ('fancon','press','brand','live','other')),
 venue text, image public.asset_url not null, source_url public.asset_url, action_url public.asset_url,
 is_demo boolean not null default false, event_status text not null default 'scheduled' check(event_status in ('scheduled','cancelled','postponed')),
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now(),
 check(ends_at is null or ends_at>starts_at), check(is_demo or status <> 'published' or source_url is not null)
);
create table public.projects (
 id text primary key, title text not null, description text not null default '', image public.asset_url not null,
 goal_amount bigint not null check(goal_amount>0), currency text not null default 'VND' check(currency='VND'),
 source_url public.asset_url, is_demo boolean not null default false,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now(),
 check(is_demo or status<>'published' or source_url is not null)
);
-- Bút toán công khai tổng hợp, không lưu tên/ngân hàng nhà tài trợ trong bảng public.
create table public.project_entries (
 id uuid primary key default gen_random_uuid(), project_id text not null references public.projects(id) on delete cascade,
 amount bigint not null check(amount<>0), entry_date date not null default current_date,
 note text not null, evidence_url public.asset_url,
 status public.publish_state not null default 'draft', updated_at timestamptz not null default now(), sort_order int not null default 0
);
create table public.editorial_entries (
 id text primary key, section text not null check(section in ('highlight','mood','letter','fact','hero')),
 title text not null, body text not null, image public.asset_url, subtitle text not null default '',
 detail text not null default '', tag text not null default '',
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.glossary (
 id text primary key, title text not null, body text not null,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.checklist_items (
 id text primary key, label text not null,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.quiz_questions (
 id text primary key, prompt text not null, solar_choice text not null, lunar_choice text not null, jummo_choice text not null,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);
create table public.downloads (
 id text primary key, title text not null, description text not null, url public.asset_url,
 kind text not null check(kind in ('mascot','sticker','wallpaper','journal','fanpack')), credit text not null,
 sort_order int not null default 0, status public.publish_state not null default 'draft', updated_at timestamptz not null default now()
);

create table private.audit_log (
 id bigint generated always as identity primary key, actor_id uuid, table_name text not null,
 action text not null, record_id text, occurred_at timestamptz not null default now(),
 before_data jsonb, after_data jsonb
);
revoke all on private.audit_log from public,anon,authenticated;
create function private.touch_updated_at() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at=now(); return new; end; $$;
create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.audit_log(actor_id,table_name,action,record_id,before_data,after_data)
 values(auth.uid(),tg_table_name,tg_op,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),to_jsonb(old),to_jsonb(new));
 return coalesce(new,old);
end; $$;
revoke all on function private.touch_updated_at(),private.audit_change() from public,anon,authenticated;

-- Cùng quy tắc xuất bản, nhưng bảng vẫn tách riêng theo nghiệp vụ để có FK/constraints.
do $$ declare t text; begin
 foreach t in array array['artists','works','media_items','tracks','events','projects','project_entries','editorial_entries','glossary','checklist_items','quiz_questions','downloads'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to anon, authenticated',t);
  execute format('grant insert,update,delete on public.%I to authenticated',t);
  execute format('create policy published_read on public.%I for select using (status=''published'' or (select private.has_role(''editor'')))',t);
  execute format('create policy editor_write on public.%I for all to authenticated using ((select private.has_role(''editor''))) with check ((select private.has_role(''editor'')))',t);
  execute format('create trigger stamp before update on public.%I for each row execute function private.touch_updated_at()',t);
  execute format('create trigger audit after insert or update or delete on public.%I for each row execute function private.audit_change()',t);
  execute format('create index on public.%I(status,sort_order)',t);
 end loop;
end; $$;
-- Một bút toán published vẫn phải có dự án published để xuất hiện công khai.
create policy parent_visible on public.project_entries as restrictive for select
 using(exists(select 1 from public.projects p where p.id=project_id));
alter table public.work_roles enable row level security;
alter table public.media_artists enable row level security;
grant select on public.work_roles,public.media_artists to anon,authenticated;
grant insert,update,delete on public.work_roles,public.media_artists to authenticated;
create policy role_read on public.work_roles for select using(exists(select 1 from public.works w where w.id=work_id) and exists(select 1 from public.artists a where a.id=artist_id));
create policy role_write on public.work_roles for all to authenticated using((select private.has_role('editor'))) with check((select private.has_role('editor')));
create policy media_people_read on public.media_artists for select using(exists(select 1 from public.media_items m where m.id=media_id) and exists(select 1 from public.artists a where a.id=artist_id));
create policy media_people_write on public.media_artists for all to authenticated using((select private.has_role('editor'))) with check((select private.has_role('editor')));
create index on public.work_roles(artist_id);
create index on public.media_artists(artist_id);
create index on public.events(starts_at) where status='published';
create index on public.project_entries(project_id);

-- Hàm đọc giữ SECURITY INVOKER: RLS vẫn áp dụng cho tất cả bảng.
create function public.get_catalog() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb='{}'; t text; rows jsonb; begin
 foreach t in array array['artists','works','work_roles','media_items','media_artists','tracks','events','projects','project_entries','editorial_entries','glossary','checklist_items','quiz_questions','downloads'] loop
  if t in ('work_roles','media_artists') then
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x',t) into rows;
  else
   -- Catalog website không đưa bản nháp vào UI kể cả khi người đọc là editor.
   execute format('select coalesce(jsonb_agg(to_jsonb(x) order by sort_order,id),''[]''::jsonb) from public.%I x where status=''published''',t) into rows;
  end if;
  result=result||jsonb_build_object(t,rows);
 end loop;
 return result;
end; $$;
revoke all on function public.get_catalog() from public;
grant execute on function public.get_catalog() to anon,authenticated;
commit;
