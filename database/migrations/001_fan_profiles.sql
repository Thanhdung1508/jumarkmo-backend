-- CHẠY 1 LẦN trong SQL Editor của dự án Supabase mới.
-- Mật khẩu/session do Supabase Auth quản lý trong auth.users, không sao chép ra public.
begin;

create table public.fan_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 50),
  created_at timestamptz not null default now()
);

-- Tạo hồ sơ cùng transaction đăng ký, tránh tài khoản thiếu hồ sơ do trình duyệt đóng sớm.
create function public.handle_new_fan()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  fan_name text;
begin
  fan_name := left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 50);
  if char_length(fan_name) < 2 then fan_name := 'Jummo Fan'; end if;
  insert into public.fan_profiles (id, display_name) values (new.id, fan_name);
  return new;
end;
$$;

revoke all on function public.handle_new_fan() from public, anon, authenticated;
create trigger on_auth_user_created_fan
after insert on auth.users
for each row execute procedure public.handle_new_fan();

-- Backfill nếu đã có tài khoản trước khi chạy migration.
insert into public.fan_profiles (id, display_name)
select id, case when char_length(btrim(coalesce(raw_user_meta_data ->> 'display_name', ''))) >= 2
  then left(btrim(raw_user_meta_data ->> 'display_name'), 50) else 'Jummo Fan' end
from auth.users on conflict (id) do nothing;

-- Bắt buộc bảo vệ dữ liệu ở database, không dựa vào việc ẩn nút trong React.
alter table public.fan_profiles enable row level security;
revoke all on public.fan_profiles from anon, authenticated;
grant select on public.fan_profiles to authenticated;
grant update (display_name) on public.fan_profiles to authenticated;

create policy "Fan chỉ xem hồ sơ của mình"
on public.fan_profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "Fan chỉ sửa tên của mình"
on public.fan_profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

commit;
