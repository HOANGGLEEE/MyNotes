begin;
create table public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  title text not null check (char_length(title) <= 200),
  body text not null check (char_length(body) <= 100000),
  pinned boolean not null default false,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);
create index notes_user_id_idx on public.notes(user_id);
alter table public.notes enable row level security;
revoke all on public.notes from anon, authenticated;
grant select, insert, update on public.notes to authenticated;
create policy notes_read on public.notes for select to authenticated using ((select auth.uid()) = user_id);
create policy notes_insert on public.notes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy notes_update on public.notes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create function public.notes_stamp() returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end;
$$;
create trigger notes_stamp before insert or update on public.notes for each row execute function public.notes_stamp();
alter publication supabase_realtime add table public.notes;
commit;
