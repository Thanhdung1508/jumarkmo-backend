-- Nội dung đã đối chiếu GMMTV ngày 30/09/2026. Chạy sau seed; có thể chạy lại.
-- Chỉ cập nhật hồ sơ và liên kết, không tác động tài khoản hoặc nội dung fan.
begin;
update public.artists set full_name_english=NULL,full_name_thai=NULL,source_url='https://www.gmm-tv.com/news/4372/',bio='Jummo là linh vật của JuniorMark thuộc GMMTV Fandom Characters.', updated_at=now() where id='jummo';
update public.artists set full_name_english='Panachai Sriariyarungruang',full_name_thai='ปณชัย ศรีอาริยะรุ่งเรือง',source_url='https://www.gmm-tv.com/artists/view/61/',bio='Nghệ sĩ trực thuộc GMMTV. Họ tên và ngày sinh được đối chiếu với hồ sơ nghệ sĩ chính thức.', updated_at=now() where id='junior';
update public.artists set full_name_english='Jiruntanin Trairattanayon',full_name_thai='จิรันธนิน ตรัยรัตนยนต์',source_url='https://www.gmm-tv.com/artists/view/82/',bio='Nghệ sĩ trực thuộc GMMTV. Họ tên và ngày sinh được đối chiếu với hồ sơ nghệ sĩ chính thức.', updated_at=now() where id='mark';
insert into public.artist_social_links (artist_id,platform,url) values ('junior','instagram','https://www.instagram.com/junniorrs/') on conflict (artist_id,platform) do update set url=excluded.url;
insert into public.artist_social_links (artist_id,platform,url) values ('junior','twitter','https://twitter.com/jnnrrs') on conflict (artist_id,platform) do update set url=excluded.url;
insert into public.artist_social_links (artist_id,platform,url) values ('junior','tiktok','https://www.tiktok.com/@jnnrrs') on conflict (artist_id,platform) do update set url=excluded.url;
insert into public.artist_social_links (artist_id,platform,url) values ('mark','instagram','https://www.instagram.com/markjrtn/') on conflict (artist_id,platform) do update set url=excluded.url;
insert into public.artist_social_links (artist_id,platform,url) values ('mark','twitter','https://twitter.com/markjrtn') on conflict (artist_id,platform) do update set url=excluded.url;
insert into public.artist_social_links (artist_id,platform,url) values ('mark','tiktok','https://www.tiktok.com/@markjrtn') on conflict (artist_id,platform) do update set url=excluded.url;
commit;
