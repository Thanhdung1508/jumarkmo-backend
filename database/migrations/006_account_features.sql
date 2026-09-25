-- Chạy sau 003_archive_items và 005_document_features. Không lưu mật khẩu trong public.
begin;
alter table public.fan_profiles add column bio text not null default '' check(char_length(bio)<=500);
grant update(bio) on public.fan_profiles to authenticated;
alter table public.archive_items drop constraint archive_items_kind_check;
alter table public.archive_items add constraint archive_items_kind_check check(kind in ('memory','event','favorite','progress','photo','page'));

create table public.user_settings (
 user_id uuid primary key references auth.users(id) on delete cascade,
 show_country boolean not null default false,
 updated_at timestamptz not null default now()
);
create table public.user_notes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(char_length(btrim(title)) between 1 and 120),
 body text not null default '' check(char_length(body)<=10000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index user_notes_owner_date on public.user_notes(user_id,updated_at desc);
do $$ declare t text; begin
 foreach t in array array['user_settings','user_notes'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,delete on public.%I to authenticated',t);
  execute format('create policy own_read on public.%I for select to authenticated using((select auth.uid())=user_id)',t);
  execute format('create policy own_insert on public.%I for insert to authenticated with check((select auth.uid())=user_id)',t);
  execute format('create policy own_update on public.%I for update to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id)',t);
  execute format('create policy own_delete on public.%I for delete to authenticated using((select auth.uid())=user_id)',t);
  execute format('create trigger stamp before update on public.%I for each row execute function private.touch_updated_at()',t);
 end loop;
end; $$;
-- Upsert gửi cả user_id; RLS vẫn ngăn đổi chủ sở hữu.
grant update(user_id,show_country) on public.user_settings to authenticated;
grant update(title,body) on public.user_notes to authenticated;

-- Lựa chọn áp dụng cho lời nhắn mới, không sửa lại bài cũ hay xác định vị trí người dùng.
create function private.apply_message_privacy() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not coalesce((select show_country from public.user_settings where user_id=new.user_id),false) then
  new.country='GLOBAL'; new.country_code='GLOBAL';
 end if;
 return new;
end; $$;
revoke all on function private.apply_message_privacy() from public,anon,authenticated;
create trigger message_privacy before insert on public.fan_messages for each row execute function private.apply_message_privacy();

-- Mọi truy vấn ràng buộc auth.uid(), danh sách bảng cố định. Không xuất session/mật khẩu/quyền nội bộ.
-- SECURITY DEFINER chỉ để đọc lời nhắn theo user_id (cột này không cấp trực tiếp cho trình duyệt).
create function public.export_my_data() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb='{}'; t text; rows jsonb; begin
 if auth.uid() is null then raise exception 'Đăng nhập để xuất dữ liệu.' using errcode='42501'; end if;
 select to_jsonb(p) into rows from public.fan_profiles p where id=auth.uid();
 result=jsonb_build_object('profile',rows);
 foreach t in array array['user_settings','user_notes','archive_items','message_likes','media_bookmarks','user_checklist','fan_progress','jummo_daily_logs'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x where user_id=auth.uid()',t) into rows;
  result=result||jsonb_build_object(t,rows);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(m)-'user_id'),'[]'::jsonb) into rows from public.fan_messages m where user_id=auth.uid();
 return result||jsonb_build_object('messages',rows);
end; $$;
revoke all on function public.export_my_data() from public,anon;
grant execute on function public.export_my_data() to authenticated;
comment on table public.user_notes is 'Ghi chú cá nhân dạng chữ thuần; chỉ chủ tài khoản đọc/sửa/xóa.';
comment on column public.user_settings.show_country is 'Cho phép hiển thị quốc gia trên lời nhắn mới. Mặc định ẩn.';
commit;
