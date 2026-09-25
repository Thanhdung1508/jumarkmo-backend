-- Bổ sung các trường và chức năng tại mục IV.2 của tài liệu Word.
-- Giữ tên bảng hiện có để đăng nhập/lời nhắn không bị gãy khi nâng cấp.
begin;

alter table public.fan_profiles add column avatar_url public.asset_url;
grant update(avatar_url) on public.fan_profiles to authenticated;

alter table public.artists
 add column full_name_english text,
 add column full_name_thai text,
 add column nickname text;
-- Link mạng xã hội tách thành bản ghi, chỉ chấp nhận HTTPS hoặc asset nội bộ.
create table public.artist_social_links (
 artist_id text not null references public.artists(id) on delete cascade,
 platform text not null check(platform in ('instagram','twitter','tiktok','youtube','facebook','website')),
 url public.asset_url not null check(url::text like 'https://%'),
 primary key(artist_id,platform)
);
alter table public.artist_social_links enable row level security;
revoke all on public.artist_social_links from public,anon,authenticated;
grant select on public.artist_social_links to anon,authenticated;
grant insert,update,delete on public.artist_social_links to authenticated;
create policy social_read on public.artist_social_links for select using(exists(select 1 from public.artists a where a.id=artist_id));
create policy social_edit on public.artist_social_links for all to authenticated using((select private.has_role('editor'))) with check((select private.has_role('editor')));

alter table public.media_items
 add column tags text[] not null default '{}',
 add column view_count bigint not null default 0 check(view_count>=0),
 add column created_at timestamptz not null default now();
alter table public.events
 add column map_url public.asset_url,
 add column stream_url public.asset_url,
 add column hashtags text[] not null default '{}',
 add column created_at timestamptz not null default now();

-- Tọa độ lưu một lần: ngôi sao không đổi chỗ mỗi lần tải trang.
alter table public.fan_messages
 add column country_code text not null default 'GLOBAL' check(country_code='GLOBAL' or country_code ~ '^[A-Z]{2}$'),
 add column position_x numeric(5,2) not null default (random()*100)::numeric(5,2) check(position_x between 0 and 100),
 add column position_y numeric(5,2) not null default (random()*100)::numeric(5,2) check(position_y between 0 and 100);
grant select(country_code,position_x,position_y) on public.fan_messages to anon,authenticated;
grant insert(country_code) on public.fan_messages to authenticated;

create table public.jummo_fortunes (
 id uuid primary key default gen_random_uuid(),
 quote_text text not null check(char_length(btrim(quote_text)) between 1 and 1000),
 author_type text not null default 'jummo' check(author_type in ('junior','mark','jummo')),
 background_url public.asset_url,
 status public.publish_state not null default 'draft',
 sort_order int not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.jummo_daily_logs (
 user_id uuid not null references auth.users(id) on delete cascade,
 fortune_id uuid not null references public.jummo_fortunes(id),
 claimed_date date not null,
 created_at timestamptz not null default now(),
 primary key(user_id,claimed_date)
);
create index on public.jummo_daily_logs(fortune_id);
create table public.jummo_secret_rewards (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 reward_type text not null check(reward_type in ('letter','video','wallpaper','sticker')),
 body text not null default '',
 content_url public.asset_url,
 status public.publish_state not null default 'draft',
 sort_order int not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(char_length(btrim(body))>0 or content_url is not null)
);
-- "Bí mật" là Easter Egg giao diện, không phải tài liệu riêng cần bảo mật.
do $$ declare t text; begin
 foreach t in array array['jummo_fortunes','jummo_secret_rewards'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to anon,authenticated',t);
  execute format('grant insert,update,delete on public.%I to authenticated',t);
  execute format('create policy published_read on public.%I for select using(status=''published'' or (select private.has_role(''editor'')))',t);
  execute format('create policy editor_write on public.%I for all to authenticated using((select private.has_role(''editor''))) with check((select private.has_role(''editor'')))',t);
  execute format('create trigger stamp before update on public.%I for each row execute function private.touch_updated_at()',t);
  execute format('create trigger audit after insert or update or delete on public.%I for each row execute function private.audit_change()',t);
  execute format('create index on public.%I(status,sort_order)',t);
 end loop;
end; $$;
alter table public.jummo_daily_logs enable row level security;
revoke all on public.jummo_daily_logs from public,anon,authenticated;
grant select on public.jummo_daily_logs to authenticated;
create policy own_claims on public.jummo_daily_logs for select to authenticated using((select auth.uid())=user_id);

-- Database quyết định ngày theo giờ Việt Nam; không tin đồng hồ trình duyệt.
-- Khóa theo tài khoản tránh hai request đồng thời nhận hai quẻ khác nhau.
create function public.claim_daily_fortune() returns public.jummo_fortunes
language plpgsql security definer set search_path='' as $$
declare fan_id uuid=auth.uid(); today date=(now() at time zone 'Asia/Ho_Chi_Minh')::date;
 chosen public.jummo_fortunes;
begin
 if fan_id is null then raise exception 'Đăng nhập để nhận quẻ.' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fortune:'||fan_id::text,0));
 select f.* into chosen from public.jummo_daily_logs l join public.jummo_fortunes f on f.id=l.fortune_id
 where l.user_id=fan_id and l.claimed_date=today;
 if found then
  -- Quẻ bị thu hồi không tiếp tục lộ nội dung qua RPC.
  if chosen.status<>'published' then raise exception 'Quẻ hôm nay đã được thu hồi.' using errcode='P0001'; end if;
  return chosen;
 end if;
 select * into chosen from public.jummo_fortunes where status='published' order by random() limit 1;
 if not found then raise exception 'Chưa có quẻ được xuất bản.' using errcode='P0001'; end if;
 insert into public.jummo_daily_logs(user_id,fortune_id,claimed_date) values(fan_id,chosen.id,today);
 return chosen;
end; $$;
revoke all on function public.claim_daily_fortune() from public,anon;
grant execute on function public.claim_daily_fortune() to authenticated;

-- Catalog cho giao diện; chỉ trả bản ghi published và liên kết của bản ghi published.
create or replace function public.get_catalog() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb='{}'; t text; rows jsonb; begin
 foreach t in array array['artists','works','media_items','tracks','events','projects','project_entries','editorial_entries','glossary','checklist_items','quiz_questions','downloads','jummo_fortunes','jummo_secret_rewards'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x) order by sort_order,id),''[]''::jsonb) from public.%I x where status=''published''',t) into rows;
  result=result||jsonb_build_object(t,rows);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows from public.work_roles r
 join public.artists a on a.id=r.artist_id and a.status='published' join public.works w on w.id=r.work_id and w.status='published';
 result=result||jsonb_build_object('work_roles',rows);
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows from public.media_artists r
 join public.artists a on a.id=r.artist_id and a.status='published' join public.media_items m on m.id=r.media_id and m.status='published';
 result=result||jsonb_build_object('media_artists',rows);
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows from public.artist_social_links r
 join public.artists a on a.id=r.artist_id and a.status='published';
 return result||jsonb_build_object('artist_social_links',rows);
end; $$;

comment on table public.artists is 'Hồ sơ Junior, Mark và Jummo; tương ứng profiles trong tài liệu.';
comment on table public.fan_profiles is 'Hồ sơ fan; email/mật khẩu ở auth.users, quyền nhân sự ở private.staff.';
comment on table public.events is 'Lịch trình; tương ứng schedules trong tài liệu. Sinh nhật tính từ artists.birthday.';
comment on table public.fan_messages is 'Sao hoặc nốt nhạc: kind=star/note. Chỉ approved được công khai.';
comment on table public.jummo_daily_logs is 'Mỗi tài khoản nhận tối đa một quẻ mỗi ngày theo giờ Việt Nam, ghi qua claim_daily_fortune.';
comment on column public.media_items.view_count is 'Lượt xem được server/editor xác nhận. Chưa nối bộ đếm từ UI; không tự tăng từ client.';
comment on column public.fan_messages.country_code is 'Mã ISO hai chữ hoặc GLOBAL; không lưu địa chỉ nhà/IP của fan.';
comment on column public.artists.full_name_english is 'Họ tên đầy đủ bằng tiếng Anh.';
comment on column public.artists.full_name_thai is 'Họ tên đầy đủ bằng tiếng Thái; để trống cho đến khi xác minh nguồn.';
commit;
