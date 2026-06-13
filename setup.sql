-- =====================================================
-- INT.LIFE Contributions System — Supabase Setup SQL
-- Run in Supabase Dashboard > SQL Editor
-- =====================================================

-- NOTE: If builders.id is NOT uuid (e.g. bigint/serial), change the
-- builder_id type in the contributions table and foreign key accordingly.
-- Check with: select column_name, data_type from information_schema.columns
--             where table_name='builders' and column_name='id';

-- 1. Storage bucket
insert into storage.buckets (id, name, public)
values ('contributions', 'contributions', true)
on conflict (id) do nothing;

-- 2. contributions table
create table if not exists public.contributions (
  id           uuid        primary key default gen_random_uuid(),
  builder_id   uuid        not null references public.builders(id) on delete cascade,
  title        text        not null,
  title_ja     text,
  description  text,
  description_ja text,
  dimension    text        not null check (dimension in (
                 'time','knowledge','health','integrity',
                 'motivation','skills','flourishing','general'
               )),
  file_url     text        not null,
  file_name    text        not null,
  file_type    text        not null,
  file_size    integer,
  is_published boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_contributions_dimension on public.contributions(dimension);
create index if not exists idx_contributions_builder   on public.contributions(builder_id);
create index if not exists idx_contributions_created   on public.contributions(created_at desc);

-- 3. RLS on contributions
alter table public.contributions enable row level security;

create policy "Public can read published contributions"
  on public.contributions for select
  using (is_published = true);

create policy "Builders can insert own contributions"
  on public.contributions for insert
  to authenticated
  with check (
    builder_id in (
      select id from public.builders
      where email = auth.jwt() ->> 'email'
    )
  );

create policy "Builders can update own contributions"
  on public.contributions for update
  to authenticated
  using (
    builder_id in (
      select id from public.builders
      where email = auth.jwt() ->> 'email'
    )
  );

create policy "Builders can delete own contributions"
  on public.contributions for delete
  to authenticated
  using (
    builder_id in (
      select id from public.builders
      where email = auth.jwt() ->> 'email'
    )
  );

-- 4. Allow authenticated users to read builders (needed for RLS subquery)
--    Only add this if builders table has RLS enabled. Safe to run either way.
do $$
begin
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'builders' and c.relrowsecurity = true
  ) then
    execute $policy$
      create policy "Authenticated can read builders"
        on public.builders for select
        to authenticated
        using (true)
    $policy$;
  end if;
exception when duplicate_object then null;
end $$;

-- 5. Storage RLS policies
create policy "Authenticated can upload to contributions"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'contributions');

create policy "Public can read contributions bucket"
  on storage.objects for select
  using (bucket_id = 'contributions');

create policy "Owner can delete own files"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'contributions' and owner = auth.uid());
