-- BuurtHub — fase 1: wijken, profielen, groepen, berichten, reacties, likes, meldingen en blokkades.
-- Uitvoeren in Supabase: SQL Editor → plak dit bestand → Run (of `supabase db push`).

create extension if not exists pgcrypto;

-- ───────────────────────── Tabellen ─────────────────────────

create table public.wijken (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  naam        text not null,
  plaats      text not null,
  postcodes   text[] not null default '{}',   -- 4-cijferige postcodes, voor zoeken
  created_at  timestamptz not null default now()
);

create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text not null default '' check (char_length(display_name) <= 60),
  avatar_path        text,
  bio                text not null default '' check (char_length(bio) <= 300),
  straat             text not null default '' check (char_length(straat) <= 80),
  wijk_id            uuid references public.wijken (id) on delete set null,
  huisregels_akkoord timestamptz,
  created_at         timestamptz not null default now()
);

-- Contactgegevens apart, zodat het 06-nummer alleen zichtbaar is als de eigenaar dat wil
create table public.profile_contact (
  id                 uuid primary key references public.profiles (id) on delete cascade,
  telefoon           text not null default '' check (char_length(telefoon) <= 20),
  telefoon_zichtbaar boolean not null default false
);

create table public.wijk_members (
  wijk_id    uuid not null references public.wijken (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  rol        text not null default 'lid' check (rol in ('lid', 'beheerder')),
  joined_at  timestamptz not null default now(),
  primary key (wijk_id, user_id)
);

create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  wijk_id     uuid not null references public.wijken (id) on delete cascade,
  soort       text not null check (soort in ('chat', 'weggeef', 'markt', 'ondernemers', 'preventie', 'eigen')),
  naam        text not null check (char_length(naam) <= 40),
  beschrijving text not null default '',
  sort        int not null default 100,
  created_at  timestamptz not null default now()
);
create index on public.groups (wijk_id, sort);

create table public.posts (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  wijk_id      uuid not null references public.wijken (id) on delete cascade,
  author_id    uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 5000),
  image_paths  text[] not null default '{}' check (cardinality(image_paths) <= 4),
  hidden       boolean not null default false,
  created_at   timestamptz not null default now(),
  edited_at    timestamptz
);
create index on public.posts (wijk_id, created_at desc);
create index on public.posts (group_id, created_at desc);

create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts (id) on delete cascade,
  author_id   uuid not null references auth.users (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  hidden      boolean not null default false,
  created_at  timestamptz not null default now()
);
create index on public.comments (post_id, created_at);

create table public.post_likes (
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  wijk_id     uuid not null references public.wijken (id) on delete cascade,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  post_id     uuid references public.posts (id) on delete cascade,
  comment_id  uuid references public.comments (id) on delete cascade,
  profile_id  uuid references public.profiles (id) on delete cascade,
  reden       text not null check (char_length(reden) between 1 and 500),
  status      text not null default 'open' check (status in ('open', 'afgehandeld')),
  created_at  timestamptz not null default now(),
  check (num_nonnulls(post_id, comment_id, profile_id) = 1)
);

create table public.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- ───────────────────────── Hulpfuncties ─────────────────────────

create or replace function public.is_wijk_member(w uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wijk_members where wijk_id = w and user_id = auth.uid());
$$;

create or replace function public.is_wijk_admin(w uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wijk_members where wijk_id = w and user_id = auth.uid() and rol = 'beheerder');
$$;

create or replace function public.is_blocked_by_me(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks where blocker_id = auth.uid() and blocked_id = u);
$$;

-- Nieuw account → leeg profiel
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id) values (new.id) on conflict do nothing;
  insert into profile_contact (id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Nieuwe wijk → vaste groepen
create or replace function public.create_default_groups() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into groups (wijk_id, soort, naam, beschrijving, sort) values
    (new.id, 'chat',        'Buurtchat',       'Alles wat speelt in de buurt', 10),
    (new.id, 'weggeef',     'Weggeefhoek',     'Gratis op te halen',           20),
    (new.id, 'markt',       'Marktplaats',     'Te koop in de buurt',          30),
    (new.id, 'ondernemers', 'Ondernemershoek', 'Ondernemers uit de wijk',      40),
    (new.id, 'preventie',   'Buurtpreventie',  'Waarschuwingen en meldingen. Bij nood eerst 112.', 50);
  return new;
end;
$$;
create trigger on_wijk_created after insert on public.wijken
  for each row execute function public.create_default_groups();

-- Lid worden van een wijk (en die als huidige wijk zetten)
create or replace function public.join_wijk(w uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into wijk_members (wijk_id, user_id) values (w, auth.uid()) on conflict do nothing;
  update profiles set wijk_id = w where id = auth.uid();
end;
$$;

-- Account verwijderen (verplicht voor de App Store); alles verdwijnt via on delete cascade
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth, storage as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  delete from storage.objects where bucket_id = 'media' and (storage.foldername(name))[1] = uid::text;
  delete from auth.users where id = uid;
end;
$$;

-- Zorg dat een bericht in de wijk van zijn groep staat
create or replace function public.posts_set_wijk() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select wijk_id into new.wijk_id from groups where id = new.group_id;
  return new;
end;
$$;
create trigger posts_set_wijk before insert on public.posts
  for each row execute function public.posts_set_wijk();

-- ───────────────────────── Weergave voor de tijdlijn ─────────────────────────

create or replace view public.posts_feed with (security_invoker = true) as
select
  p.id, p.group_id, p.wijk_id, p.author_id, p.body, p.image_paths, p.hidden, p.created_at, p.edited_at,
  g.naam  as group_naam,
  g.soort as group_soort,
  pr.display_name as author_name,
  pr.avatar_path  as author_avatar,
  (select count(*) from post_likes l where l.post_id = p.id)::int as like_count,
  (select count(*) from comments c where c.post_id = p.id and not c.hidden)::int as comment_count,
  exists (select 1 from post_likes l where l.post_id = p.id and l.user_id = auth.uid()) as liked_by_me
from posts p
join groups g on g.id = p.group_id
join profiles pr on pr.id = p.author_id;

create or replace view public.comments_feed with (security_invoker = true) as
select c.id, c.post_id, c.author_id, c.body, c.hidden, c.created_at,
       pr.display_name as author_name, pr.avatar_path as author_avatar
from comments c join profiles pr on pr.id = c.author_id;

-- ───────────────────────── Beveiliging (RLS) ─────────────────────────

alter table public.wijken       enable row level security;
alter table public.profiles     enable row level security;
alter table public.wijk_members enable row level security;
alter table public.groups       enable row level security;
alter table public.posts        enable row level security;
alter table public.comments     enable row level security;
alter table public.post_likes   enable row level security;
alter table public.reports      enable row level security;
alter table public.blocks       enable row level security;

-- Wijken: iedereen die is ingelogd mag de lijst zien (om er een te kiezen)
create policy "wijken lezen" on public.wijken for select to authenticated using (true);

-- Profielen: jezelf, en buren in een gedeelde wijk
create policy "profiel lezen" on public.profiles for select to authenticated
  using (id = auth.uid() or exists (
    select 1 from wijk_members a join wijk_members b on a.wijk_id = b.wijk_id
    where a.user_id = auth.uid() and b.user_id = profiles.id));
create policy "profiel eigen wijzigen" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Telefoonnummer: zelf altijd, buren alleen als de eigenaar het zichtbaar zet
alter table public.profile_contact enable row level security;
create policy "contact lezen" on public.profile_contact for select to authenticated
  using (id = auth.uid() or (telefoon_zichtbaar and exists (
    select 1 from wijk_members a join wijk_members b on a.wijk_id = b.wijk_id
    where a.user_id = auth.uid() and b.user_id = profile_contact.id)));
create policy "contact eigen wijzigen" on public.profile_contact for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Wijkleden
create policy "leden lezen" on public.wijk_members for select to authenticated
  using (is_wijk_member(wijk_id));
create policy "leden rol wijzigen" on public.wijk_members for update to authenticated
  using (is_wijk_admin(wijk_id)) with check (is_wijk_admin(wijk_id));
create policy "zelf wijk verlaten" on public.wijk_members for delete to authenticated
  using (user_id = auth.uid() or is_wijk_admin(wijk_id));

-- Groepen
create policy "groepen lezen" on public.groups for select to authenticated using (is_wijk_member(wijk_id));
create policy "groepen beheren" on public.groups for all to authenticated
  using (is_wijk_admin(wijk_id)) with check (is_wijk_admin(wijk_id));

-- Berichten
create policy "berichten lezen" on public.posts for select to authenticated
  using (is_wijk_member(wijk_id) and (not hidden or author_id = auth.uid() or is_wijk_admin(wijk_id))
         and not is_blocked_by_me(author_id));
create policy "bericht plaatsen" on public.posts for insert to authenticated
  with check (author_id = auth.uid() and exists (
    select 1 from groups g where g.id = group_id and is_wijk_member(g.wijk_id)));
create policy "eigen bericht wijzigen" on public.posts for update to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id))
  with check (author_id = auth.uid() or is_wijk_admin(wijk_id));
create policy "eigen bericht verwijderen" on public.posts for delete to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id));

-- Reacties
create policy "reacties lezen" on public.comments for select to authenticated
  using (exists (select 1 from posts p where p.id = post_id)  -- erft de regels van posts
         and (not hidden or author_id = auth.uid())
         and not is_blocked_by_me(author_id));
create policy "reactie plaatsen" on public.comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from posts p where p.id = post_id));
create policy "eigen reactie verwijderen" on public.comments for delete to authenticated
  using (author_id = auth.uid() or exists (
    select 1 from posts p where p.id = post_id and is_wijk_admin(p.wijk_id)));
create policy "reactie verbergen" on public.comments for update to authenticated
  using (exists (select 1 from posts p where p.id = post_id and is_wijk_admin(p.wijk_id)));

-- Likes
create policy "likes lezen" on public.post_likes for select to authenticated
  using (exists (select 1 from posts p where p.id = post_id));
create policy "like geven" on public.post_likes for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from posts p where p.id = post_id));
create policy "like weghalen" on public.post_likes for delete to authenticated using (user_id = auth.uid());

-- Meldingen: iedereen mag melden, beheerders zien en handelen af
create policy "melden" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and is_wijk_member(wijk_id));
create policy "meldingen lezen" on public.reports for select to authenticated
  using (reporter_id = auth.uid() or is_wijk_admin(wijk_id));
create policy "melding afhandelen" on public.reports for update to authenticated
  using (is_wijk_admin(wijk_id)) with check (is_wijk_admin(wijk_id));

-- Blokkades: alleen je eigen
create policy "eigen blokkades" on public.blocks for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

grant execute on function public.join_wijk(uuid), public.delete_my_account() to authenticated;

-- ───────────────────────── Opslag voor foto's ─────────────────────────
-- Openbare bucket met onraadbare paden: <user-id>/<uuid>.jpg

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "media uploaden in eigen map" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "media eigen verwijderen" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ───────────────────────── Startdata ─────────────────────────

insert into public.wijken (slug, naam, plaats, postcodes)
values ('zuidbroek', 'Zuidbroek', 'Apeldoorn', '{}')  -- postcodes vul je later aan
on conflict (slug) do nothing;
