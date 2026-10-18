create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id)
);

alter table public.members enable row level security;

drop policy if exists "Authenticated users can read members"
  on public.members;
create policy "Authenticated users can read members"
  on public.members for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

drop policy if exists "Authenticated users can add members"
  on public.members;
create policy "Authenticated users can add members"
  on public.members for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true'
    and auth.uid() = created_by
  );

grant select, insert on public.members to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'members'
  ) then
    alter publication supabase_realtime add table public.members;
  end if;
end
$$;

create table if not exists public.monthly_savings (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete restrict,
  contribution_month date not null,
  paid_on date not null default current_date,
  amount integer not null default 500 check (amount = 500),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  constraint monthly_savings_one_per_member_month
    unique (member_id, contribution_month),
  constraint monthly_savings_month_starts_on_first
    check (extract(day from contribution_month) = 1)
);

alter table public.monthly_savings enable row level security;

drop policy if exists "Admins can read monthly savings"
  on public.monthly_savings;
create policy "Admins can read monthly savings"
  on public.monthly_savings for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

drop policy if exists "Admins can record monthly savings"
  on public.monthly_savings;
create policy "Admins can record monthly savings"
  on public.monthly_savings for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true'
    and auth.uid() = created_by
  );

grant select, insert on public.monthly_savings to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'monthly_savings'
  ) then
    alter publication supabase_realtime add table public.monthly_savings;
  end if;
end
$$;
