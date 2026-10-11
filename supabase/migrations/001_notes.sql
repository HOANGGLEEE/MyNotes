begin;
create table public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  title text not null check (char_length(title) <= 200),
  body text not null check (char_length(body) <= 100000),
  pinned boolean not null default false,
  deleted boolean not null default false,
  revision bigint not null default 1,
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

-- SECURITY DEFINER intentionally used so the transaction can atomically
-- compare revisions. auth.uid() is always checked inside the function.
create or replace function public.save_note_if_revision(
  p_id uuid, p_title text, p_body text, p_pinned boolean,
  p_deleted boolean, p_expected_revision bigint
) returns bigint language plpgsql security definer
set search_path = '' as $$
declare current_revision bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if length(p_title) > 200 or length(p_body) > 100000 then
    raise exception 'Note too long' using errcode = '22001';
  end if;
  if p_expected_revision = 0 then
    insert into public.notes(id,user_id,title,body,pinned,deleted,revision)
    values(p_id, auth.uid(), p_title,p_body,p_pinned,p_deleted,1)
    on conflict (id) do nothing
    returning revision into current_revision;
    return current_revision;
  end if;
  update public.notes
     set title=p_title,body=p_body,pinned=p_pinned,deleted=p_deleted,
         revision=revision+1
   where id=p_id and user_id=auth.uid() and revision=p_expected_revision
   returning revision into current_revision;
  return current_revision;
end; $$;
revoke all on function public.save_note_if_revision(uuid,text,text,boolean,boolean,bigint) from public;
grant execute on function public.save_note_if_revision(uuid,text,text,boolean,boolean,bigint) to authenticated;
