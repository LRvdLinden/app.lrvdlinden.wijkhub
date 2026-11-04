-- WijkHub — fase 2: marktplaats & weggeefhoek, hulp & diensten, privéberichten.
-- Uitvoeren ná 20261104000000_init.sql.

-- ───────────────────────── Marktplaats & weggeefhoek ─────────────────────────

create table public.listings (
  id           uuid primary key default gen_random_uuid(),
  wijk_id      uuid not null references public.wijken (id) on delete cascade,
  author_id    uuid not null references auth.users (id) on delete cascade,
  soort        text not null check (soort in ('markt', 'weggeef')),
  titel        text not null check (char_length(titel) between 2 and 80),
  beschrijving text not null default '' check (char_length(beschrijving) <= 3000),
  prijs_type   text not null default 'vast' check (prijs_type in ('vast', 'bieden', 'gratis')),
  prijs_cent   int check (prijs_cent is null or prijs_cent between 0 and 100000000),
  categorie    text not null default 'overig',
  image_paths  text[] not null default '{}' check (cardinality(image_paths) <= 6),
  status       text not null default 'beschikbaar' check (status in ('beschikbaar', 'gereserveerd', 'verkocht')),
  hidden       boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (soort = 'markt' or prijs_type = 'gratis')
);
create index on public.listings (wijk_id, created_at desc);

create table public.help_items (
  id           uuid primary key default gen_random_uuid(),
  wijk_id      uuid not null references public.wijken (id) on delete cascade,
  author_id    uuid not null references auth.users (id) on delete cascade,
  soort        text not null check (soort in ('aanbod', 'vraag')),
  categorie    text not null default 'overig',
  titel        text not null check (char_length(titel) between 2 and 80),
  beschrijving text not null default '' check (char_length(beschrijving) <= 3000),
  status       text not null default 'open' check (status in ('open', 'afgerond')),
  hidden       boolean not null default false,
  created_at   timestamptz not null default now()
);
create index on public.help_items (wijk_id, created_at desc);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;
create trigger listings_touch before update on public.listings for each row execute function public.touch_updated_at();

create or replace view public.listings_feed with (security_invoker = true) as
select l.*, pr.display_name as author_name, pr.avatar_path as author_avatar
from listings l join profiles pr on pr.id = l.author_id;

create or replace view public.help_feed with (security_invoker = true) as
select h.*, pr.display_name as author_name, pr.avatar_path as author_avatar
from help_items h join profiles pr on pr.id = h.author_id;

alter table public.listings   enable row level security;
alter table public.help_items enable row level security;

create policy "advertenties lezen" on public.listings for select to authenticated
  using (is_wijk_member(wijk_id) and (not hidden or author_id = auth.uid() or is_wijk_admin(wijk_id))
         and not is_blocked_by_me(author_id));
create policy "advertentie plaatsen" on public.listings for insert to authenticated
  with check (author_id = auth.uid() and is_wijk_member(wijk_id));
create policy "advertentie wijzigen" on public.listings for update to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id))
  with check (author_id = auth.uid() or is_wijk_admin(wijk_id));
create policy "advertentie verwijderen" on public.listings for delete to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id));

create policy "hulp lezen" on public.help_items for select to authenticated
  using (is_wijk_member(wijk_id) and (not hidden or author_id = auth.uid() or is_wijk_admin(wijk_id))
         and not is_blocked_by_me(author_id));
create policy "hulp plaatsen" on public.help_items for insert to authenticated
  with check (author_id = auth.uid() and is_wijk_member(wijk_id));
create policy "hulp wijzigen" on public.help_items for update to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id))
  with check (author_id = auth.uid() or is_wijk_admin(wijk_id));
create policy "hulp verwijderen" on public.help_items for delete to authenticated
  using (author_id = auth.uid() or is_wijk_admin(wijk_id));

-- ───────────────────────── Privéberichten ─────────────────────────

create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  wijk_id         uuid not null references public.wijken (id) on delete cascade,
  listing_id      uuid references public.listings (id) on delete set null,
  help_id         uuid references public.help_items (id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index on public.conversation_members (user_id);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null references auth.users (id) on delete cascade,
  body            text not null check (char_length(body) between 1 and 4000),
  created_at      timestamptz not null default now()
);
create index on public.messages (conversation_id, created_at);

create or replace function public.is_conversation_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from conversation_members where conversation_id = c and user_id = auth.uid());
$$;

-- De andere deelnemer van een gesprek (1-op-1)
create or replace function public.conversation_partner(c uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select user_id from conversation_members where conversation_id = c and user_id <> auth.uid() limit 1;
$$;

-- Bestaand gesprek met deze buur openen, of een nieuw beginnen
create or replace function public.start_conversation(other uuid, listing uuid default null, help uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  w uuid;
  conv uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if other = me then raise exception 'cannot message yourself'; end if;
  select a.wijk_id into w from wijk_members a join wijk_members b on a.wijk_id = b.wijk_id
    where a.user_id = me and b.user_id = other limit 1;
  if w is null then raise exception 'not in the same neighbourhood'; end if;
  if exists (select 1 from blocks where (blocker_id = me and blocked_id = other) or (blocker_id = other and blocked_id = me)) then
    raise exception 'blocked';
  end if;

  select c.id into conv from conversations c
    join conversation_members m1 on m1.conversation_id = c.id and m1.user_id = me
    join conversation_members m2 on m2.conversation_id = c.id and m2.user_id = other
    order by c.last_message_at desc limit 1;

  if conv is null then
    insert into conversations (wijk_id, listing_id, help_id) values (w, listing, help) returning id into conv;
    insert into conversation_members (conversation_id, user_id) values (conv, me), (conv, other);
  elsif listing is not null or help is not null then
    update conversations set listing_id = coalesce(listing, listing_id), help_id = coalesce(help, help_id) where id = conv;
  end if;
  return conv;
end;
$$;

create or replace function public.mark_conversation_read(c uuid) returns void
language sql security definer set search_path = public as $$
  update conversation_members set last_read_at = now() where conversation_id = c and user_id = auth.uid();
$$;

create or replace function public.messages_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update conversations set last_message_at = new.created_at where id = new.conversation_id;
  update conversation_members set last_read_at = new.created_at
    where conversation_id = new.conversation_id and user_id = new.sender_id;
  return new;
end;
$$;
create trigger messages_after_insert after insert on public.messages
  for each row execute function public.messages_after_insert();

-- Overzicht van mijn gesprekken met de andere deelnemer, laatste bericht en ongelezen aantal
create or replace view public.conversations_overview with (security_invoker = true) as
select
  c.id, c.wijk_id, c.listing_id, c.help_id, c.last_message_at,
  other.user_id as partner_id,
  pr.display_name as partner_name,
  pr.avatar_path as partner_avatar,
  l.titel as listing_titel,
  h.titel as help_titel,
  (select m.body from messages m where m.conversation_id = c.id order by m.created_at desc limit 1) as last_body,
  (select m.sender_id from messages m where m.conversation_id = c.id order by m.created_at desc limit 1) as last_sender,
  (select count(*) from messages m where m.conversation_id = c.id and m.sender_id <> auth.uid()
     and m.created_at > me.last_read_at)::int as unread
from conversations c
join conversation_members me on me.conversation_id = c.id and me.user_id = auth.uid()
join conversation_members other on other.conversation_id = c.id and other.user_id <> auth.uid()
join profiles pr on pr.id = other.user_id
left join listings l on l.id = c.listing_id
left join help_items h on h.id = c.help_id
where exists (select 1 from messages m where m.conversation_id = c.id);

alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

create policy "gesprek lezen" on public.conversations for select to authenticated
  using (is_conversation_member(id));
create policy "deelnemers lezen" on public.conversation_members for select to authenticated
  using (is_conversation_member(conversation_id));
create policy "berichten lezen" on public.messages for select to authenticated
  using (is_conversation_member(conversation_id));
create policy "bericht sturen" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and is_conversation_member(conversation_id)
              and not exists (select 1 from blocks b
                              where b.blocker_id = conversation_partner(conversation_id) and b.blocked_id = auth.uid())
              and not is_blocked_by_me(conversation_partner(conversation_id)));

grant execute on function public.start_conversation(uuid, uuid, uuid), public.mark_conversation_read(uuid)
  to authenticated;

-- Live bijwerken van de chat
alter publication supabase_realtime add table public.messages;

-- ───────────────────────── Meldingen uitbreiden ─────────────────────────

alter table public.reports add column listing_id uuid references public.listings (id) on delete cascade;
alter table public.reports add column help_id uuid references public.help_items (id) on delete cascade;
alter table public.reports drop constraint if exists reports_check;
alter table public.reports add constraint reports_one_target
  check (num_nonnulls(post_id, comment_id, profile_id, listing_id, help_id) = 1);
