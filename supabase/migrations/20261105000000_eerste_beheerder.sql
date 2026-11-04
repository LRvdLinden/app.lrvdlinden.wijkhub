-- Wie als eerste lid wordt van een wijk zonder beheerder, wordt automatisch beheerder.
create or replace function public.join_wijk(w uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into wijk_members (wijk_id, user_id, rol)
  values (w, auth.uid(),
          case when exists (select 1 from wijk_members where wijk_id = w and rol = 'beheerder') then 'lid' else 'beheerder' end)
  on conflict do nothing;
  update profiles set wijk_id = w where id = auth.uid();
end;
$$;
