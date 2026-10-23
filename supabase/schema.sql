create table public.claims (
  owner_id uuid not null default auth.uid() references auth.users on delete cascade,
  owner_name text not null check (char_length(owner_name) <= 40),
  session_id text not null check (session_id ~ '^[A-Za-z0-9-]{1,64}$'),
  repo_key text not null check (char_length(repo_key) <= 200),
  branch text check (char_length(branch) <= 200),
  topic text not null check (char_length(topic) <= 80),
  open_topics text[] not null default '{}' check (cardinality(open_topics) <= 5),
  working boolean not null,
  last_request_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, session_id)
);
alter table public.claims enable row level security;
create policy claims_read on public.claims for select to authenticated using (true);
create policy claims_insert on public.claims for insert to authenticated with check (owner_id = auth.uid());
create policy claims_update on public.claims for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy claims_delete on public.claims for delete to authenticated using (owner_id = auth.uid());
-- upsert'te updated_at yenilensin
create or replace function public.touch_claims() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger claims_touch before insert or update on public.claims for each row execute function public.touch_claims();
