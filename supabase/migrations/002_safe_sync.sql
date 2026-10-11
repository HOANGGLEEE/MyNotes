-- Run this ONLY on existing installations of 001_notes.sql.
-- For fresh installations 001_notes.sql already includes these changes.
begin;
alter table public.notes add column if not exists revision bigint not null default 1;
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
    values(p_id,auth.uid(),p_title,p_body,p_pinned,p_deleted,1)
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
commit;
