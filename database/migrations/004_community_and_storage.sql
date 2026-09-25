begin;
revoke all on public.work_roles,public.media_artists from anon,authenticated;
grant select on public.work_roles,public.media_artists to anon,authenticated;
grant insert,update,delete on public.work_roles,public.media_artists to authenticated;

create table public.message_likes (
 user_id uuid references auth.users(id) on delete cascade,
 message_id uuid references public.fan_messages(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(user_id,message_id)
);
create table public.media_bookmarks (
 user_id uuid references auth.users(id) on delete cascade,
 media_id text references public.media_items(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(user_id,media_id)
);
create table public.user_checklist (
 user_id uuid references auth.users(id) on delete cascade,
 item_id text references public.checklist_items(id) on delete cascade,
 completed_at timestamptz not null default now(), primary key(user_id,item_id)
);
-- Kỷ niệm riêng, không phải quyền truy cập hay chứng chỉ có giá trị xác thực.
create table public.fan_progress (
 user_id uuid references auth.users(id) on delete cascade,
 kind text check(kind in ('quiz','baby_fan_certificate')),
 data jsonb not null check(jsonb_typeof(data)='object' and octet_length(data::text)<=4096),
 updated_at timestamptz not null default now(), primary key(user_id,kind)
);
do $$ declare t text; begin
 foreach t in array array['message_likes','media_bookmarks','user_checklist','fan_progress'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,delete on public.%I to authenticated',t);
  execute format('create policy own_read on public.%I for select to authenticated using ((select auth.uid())=user_id)',t);
  execute format('create policy own_delete on public.%I for delete to authenticated using ((select auth.uid())=user_id)',t);
 end loop;
end; $$;
create policy like_approved on public.message_likes for insert to authenticated with check((select auth.uid())=user_id and exists(select 1 from public.fan_messages m where m.id=message_id and m.status='approved'));
create policy bookmark_published on public.media_bookmarks for insert to authenticated with check((select auth.uid())=user_id and exists(select 1 from public.media_items m where m.id=media_id and m.status='published'));
create policy checklist_published on public.user_checklist for insert to authenticated with check((select auth.uid())=user_id and exists(select 1 from public.checklist_items c where c.id=item_id and c.status='published'));
create policy progress_own on public.fan_progress for insert to authenticated with check((select auth.uid())=user_id);
grant update(data,updated_at) on public.fan_progress to authenticated;
create policy progress_update on public.fan_progress for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
create index on public.message_likes(message_id);
create index on public.media_bookmarks(media_id);
create index on public.user_checklist(item_id);

-- Trigger chạy trong cùng transaction, khóa theo người gửi để không lách bằng request song song.
-- Nhật ký riêng giữ lượt gửi khi fan xóa bài; không thể xóa rồi gửi lại để vượt giới hạn.
create table private.message_submissions (
 user_id uuid not null references auth.users(id) on delete cascade,
 submitted_at timestamptz not null default now()
);
revoke all on private.message_submissions from public,anon,authenticated;
create index on private.message_submissions(user_id,submitted_at);
create function private.limit_messages() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,0));
 delete from private.message_submissions where user_id=new.user_id and submitted_at<=now()-interval '10 minutes';
 if (select count(*) from private.message_submissions where user_id=new.user_id)>=5 then
  raise exception 'Gửi tối đa 5 lời nhắn trong 10 phút.' using errcode='P0001';
 end if;
 insert into private.message_submissions(user_id) values(new.user_id);
 return new;
end; $$;
revoke all on function private.limit_messages() from public,anon,authenticated;
create trigger message_rate_limit before insert on public.fan_messages for each row execute function private.limit_messages();
create index on public.fan_messages(user_id,created_at desc);
create trigger message_audit after update or delete on public.fan_messages for each row execute function private.audit_change();
grant delete on public.fan_messages to authenticated;
create policy own_message_delete on public.fan_messages for delete to authenticated using((select auth.uid())=user_id);
-- Cho phép chủ bài nhìn trạng thái pending, nhưng không lộ user_id qua column grants hiện có.
create policy own_message_read on public.fan_messages for select to authenticated using((select auth.uid())=user_id or (select private.has_role('moderator')));

create function public.moderate_message(p_id uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role('moderator') then raise exception 'Không có quyền duyệt bài.' using errcode='42501'; end if;
 if p_status not in ('approved','rejected','pending') or p_status is null then raise exception 'Trạng thái không hợp lệ.'; end if;
 update public.fan_messages set status=p_status where id=p_id;
 if not found then raise exception 'Không tìm thấy lời nhắn.'; end if;
end; $$;
revoke all on function public.moderate_message(uuid,text) from public;
grant execute on function public.moderate_message(uuid,text) to authenticated;

-- Chỉ trả cột công khai và bài đã duyệt; cursor kép tránh mất bản ghi cùng timestamp.
create function public.get_message_feed(p_kind text,p_before timestamptz default null,p_before_id uuid default null,p_limit int default 20)
returns table(id uuid,name text,country text,body text,spectrum text,created_at timestamptz,like_count bigint)
language sql stable security definer set search_path='' as $$
 select m.id,m.name,m.country,m.body,m.spectrum,m.created_at,(select count(*) from public.message_likes l where l.message_id=m.id)
 from public.fan_messages m where m.kind=p_kind and m.status='approved'
 and (p_before is null or (m.created_at,m.id)<(p_before,p_before_id))
 order by m.created_at desc,m.id desc limit least(greatest(coalesce(p_limit,20),1),50);
$$;
create function public.get_community_stats(p_kind text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('messages',count(*),'locations',count(distinct lower(btrim(country))),
 'likes',(select count(*) from public.message_likes l join public.fan_messages m2 on m2.id=l.message_id where m2.kind=p_kind and m2.status='approved'))
 from public.fan_messages where kind=p_kind and status='approved';
$$;
revoke all on function public.get_message_feed(text,timestamptz,uuid,int),public.get_community_stats(text) from public;
grant execute on function public.get_message_feed(text,timestamptz,uuid,int),public.get_community_stats(text) to anon,authenticated;

-- Public bucket chỉ chứa file đã sẵn sàng công khai. Bản nháp để ở bucket private.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('site-media','site-media',true,52428800,array['image/jpeg','image/png','image/webp','image/gif','audio/mpeg','audio/ogg','video/mp4','application/pdf','application/zip']),
 ('editorial-drafts','editorial-drafts',false,52428800,array['image/jpeg','image/png','image/webp','image/gif','audio/mpeg','audio/ogg','video/mp4','application/pdf','application/zip'])
 on conflict(id) do nothing;
create policy editorial_storage_read on storage.objects for select to authenticated using(bucket_id in ('site-media','editorial-drafts') and (select private.has_role('editor')));
create policy editorial_storage_insert on storage.objects for insert to authenticated with check(bucket_id in ('site-media','editorial-drafts') and (select private.has_role('editor')));
create policy editorial_storage_update on storage.objects for update to authenticated using(bucket_id in ('site-media','editorial-drafts') and (select private.has_role('editor'))) with check(bucket_id in ('site-media','editorial-drafts') and (select private.has_role('editor')));
create policy editorial_storage_delete on storage.objects for delete to authenticated using(bucket_id in ('site-media','editorial-drafts') and (select private.has_role('editor')));
commit;
