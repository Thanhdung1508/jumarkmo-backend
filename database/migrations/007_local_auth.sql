-- CHỈ CHO BACKEND NODE LOCAL. Không đưa file này vào setup Supabase cloud.
begin;
create table if not exists private.local_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text unique not null check(email=lower(email)),
 password_hash text not null,
 created_at timestamptz not null default now()
);
create table if not exists private.local_sessions (
 token_hash text primary key,
 user_id uuid not null references private.local_accounts(user_id) on delete cascade,
 recovery boolean not null default false,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '7 days'
);
create index if not exists local_sessions_user on private.local_sessions(user_id);
create table if not exists private.local_password_resets (
 token_hash text primary key,
 user_id uuid not null references private.local_accounts(user_id) on delete cascade,
 expires_at timestamptz not null default now()+interval '30 minutes'
);
create table if not exists private.local_auth_limits (
 key text primary key,
 hits int not null default 1,
 expires_at timestamptz not null
);
revoke all on private.local_accounts,private.local_sessions,private.local_password_resets,private.local_auth_limits from public,anon,authenticated;
commit;
