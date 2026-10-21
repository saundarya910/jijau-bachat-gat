create table if not exists public.investors (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id)
);

create table if not exists public.investor_transactions (
  id uuid primary key default gen_random_uuid(),
  investor_id uuid not null references public.investors(id) on delete restrict,
  transaction_type text not null
    check (transaction_type in ('contribution', 'interest_payout', 'principal_payout')),
  amount numeric(12, 2) not null check (amount > 0),
  transaction_date date not null check (transaction_date <= current_date),
  payment_method text not null check (payment_method in ('cash', 'upi')),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id)
);

delete from public.investor_transactions
where transaction_type in ('interest_return', 'principal_return');

alter table public.investor_transactions
  drop constraint if exists investor_transactions_transaction_type_check;
alter table public.investor_transactions
  drop constraint if exists investor_transaction_source_matches_type;
alter table public.investor_transactions
  drop constraint if exists investor_transaction_source_unique;
alter table public.investor_transactions
  drop column if exists source_repayment_id;
alter table public.investor_transactions
  add constraint investor_transactions_transaction_type_check
  check (
    transaction_type in ('contribution', 'interest_payout', 'principal_payout')
  );

with canonical_investors as (
  select
    id,
    first_value(id) over (
      partition by lower(btrim(name))
      order by created_at, id
    ) as canonical_id
  from public.investors
)
update public.investor_transactions it
set investor_id = canonical.canonical_id
from canonical_investors canonical
where it.investor_id = canonical.id
  and canonical.id <> canonical.canonical_id;

with canonical_investors as (
  select
    id,
    first_value(id) over (
      partition by lower(btrim(name))
      order by created_at, id
    ) as canonical_id
  from public.investors
)
delete from public.investors investor
using canonical_investors canonical
where investor.id = canonical.id
  and canonical.id <> canonical.canonical_id;

create index if not exists investor_transactions_investor_date_idx
  on public.investor_transactions(investor_id, transaction_date, created_at);
create unique index if not exists investors_normalized_name_idx
  on public.investors(lower(btrim(name)));

alter table public.investors enable row level security;
alter table public.investor_transactions enable row level security;

drop policy if exists "Admins can read investors" on public.investors;
create policy "Admins can read investors"
  on public.investors for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

drop policy if exists "Admins can read investor transactions"
  on public.investor_transactions;
create policy "Admins can read investor transactions"
  on public.investor_transactions for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

grant select on public.investors, public.investor_transactions to authenticated;

create or replace function public.investor_balances(p_as_of date)
returns table (
  investor_id uuid,
  name text,
  principal_remaining numeric,
  interest_due numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true'
    and session_user not in ('postgres', 'supabase_admin')
  then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_as_of is null or p_as_of > current_date then
    raise exception using errcode = '22023', message = 'Balance date cannot be in the future.';
  end if;

  return query
  with month_starts as (
    select generated.month_start::date as month_start
    from (
      select min(date_trunc('month', transaction_date) + interval '1 month') as first_month
      from public.investor_transactions
      where transaction_type = 'contribution'
        and transaction_date <= p_as_of
    ) first_contribution
    cross join lateral generate_series(
      first_contribution.first_month,
      date_trunc('month', p_as_of)::date,
      interval '1 month'
    ) generated(month_start)
    where first_contribution.first_month is not null
  ),
  principal_by_month as (
    select
      investor.id as investor_id,
      months.month_start,
      greatest(
        coalesce((
          select sum(contribution.amount)
          from public.investor_transactions contribution
          where contribution.investor_id = investor.id
            and contribution.transaction_type = 'contribution'
            and contribution.transaction_date < months.month_start
        ), 0)
        -
        coalesce((
          select sum(returned.amount)
          from public.investor_transactions returned
          where returned.investor_id = investor.id
            and returned.transaction_type = 'principal_payout'
            and returned.transaction_date < months.month_start
        ), 0),
        0
      ) as principal
    from public.investors investor
    cross join month_starts months
  ),
  accrued_by_investor as (
    select
      monthly_principal.investor_id,
      sum(round(monthly_principal.principal * 0.02, 2)) as accrued_interest
    from principal_by_month monthly_principal
    group by monthly_principal.investor_id
  )
  select
    investor.id,
    investor.name,
    greatest(
      coalesce((
        select sum(contribution.amount)
        from public.investor_transactions contribution
        where contribution.investor_id = investor.id
          and contribution.transaction_type = 'contribution'
          and contribution.transaction_date <= p_as_of
      ), 0)
      -
      coalesce((
        select sum(returned.amount)
        from public.investor_transactions returned
        where returned.investor_id = investor.id
          and returned.transaction_type = 'principal_payout'
          and returned.transaction_date <= p_as_of
      ), 0),
      0
    ),
    greatest(
      coalesce(accrued.accrued_interest, 0)
      -
      coalesce((
        select sum(returned.amount)
        from public.investor_transactions returned
        where returned.investor_id = investor.id
          and returned.transaction_type = 'interest_payout'
          and returned.transaction_date <= p_as_of
      ), 0),
      0
    )
  from public.investors investor
  left join accrued_by_investor accrued on accrued.investor_id = investor.id
  order by investor.name, investor.id;
end;
$$;

revoke all on function public.investor_balances(date) from public;
grant execute on function public.investor_balances(date) to authenticated;

create or replace function public.add_investor_contribution(
  p_investor_id uuid,
  p_investor_name text,
  p_amount numeric,
  p_transaction_date date,
  p_payment_method text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_investor_id uuid;
  v_transaction_id uuid;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true'
    and session_user not in ('postgres', 'supabase_admin')
  then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_amount is null
    or p_amount <= 0
    or p_amount <> round(p_amount, 2)
    or p_transaction_date is null
    or p_transaction_date > current_date
    or p_payment_method is null
    or p_payment_method not in ('cash', 'upi')
  then
    raise exception using errcode = '22023', message = 'Enter a positive amount, valid date, and cash or UPI method.';
  end if;

  if p_investor_id is null then
    if p_investor_name is null
      or length(trim(p_investor_name)) not between 1 and 120
    then
      raise exception using errcode = '22023', message = 'Investor name is required.';
    end if;

    select id into v_investor_id
    from public.investors
    where lower(btrim(name)) = lower(btrim(p_investor_name))
    order by created_at, id
    limit 1;

    if not found then
      insert into public.investors (name, created_by)
      values (trim(p_investor_name), auth.uid())
      on conflict (lower(btrim(name))) do nothing
      returning id into v_investor_id;

      if v_investor_id is null then
        select id into v_investor_id
        from public.investors
        where lower(btrim(name)) = lower(btrim(p_investor_name));
      end if;
    end if;
  else
    select id into v_investor_id
    from public.investors
    where id = p_investor_id;

    if not found then
      raise exception using errcode = 'P0002', message = 'Investor not found.';
    end if;
  end if;

  insert into public.investor_transactions (
    investor_id,
    transaction_type,
    amount,
    transaction_date,
    payment_method,
    created_by
  )
  values (
    v_investor_id,
    'contribution',
    p_amount,
    p_transaction_date,
    p_payment_method,
    auth.uid()
  )
  returning id into v_transaction_id;

  return v_investor_id;
end;
$$;

revoke all on function public.add_investor_contribution(
  uuid,
  text,
  numeric,
  date,
  text
) from public;
grant execute on function public.add_investor_contribution(
  uuid,
  text,
  numeric,
  date,
  text
) to authenticated;

drop function if exists public.rebuild_investor_repayment_waterfall();
drop function if exists public.apply_investor_repayment_waterfall(
  numeric,
  date,
  text,
  uuid
);

create or replace function public.record_investor_payout(
  p_investor_id uuid,
  p_interest_amount numeric,
  p_principal_amount numeric,
  p_paid_on date,
  p_payment_method text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance record;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true' then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_interest_amount is null
    or p_interest_amount < 0
    or p_interest_amount <> round(p_interest_amount, 2)
    or p_principal_amount is null
    or p_principal_amount < 0
    or p_principal_amount <> round(p_principal_amount, 2)
    or p_interest_amount + p_principal_amount <= 0
    or p_paid_on is null
    or p_paid_on > current_date
    or p_payment_method is null
    or p_payment_method not in ('cash', 'upi')
  then
    raise exception using errcode = '22023', message = 'Enter valid positive payout amounts, a valid date, and cash or UPI.';
  end if;

  select *
  into v_balance
  from public.investor_balances(p_paid_on) balance
  where balance.investor_id = p_investor_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Investor not found.';
  end if;

  if p_interest_amount > v_balance.interest_due
    or p_principal_amount > v_balance.principal_remaining
  then
    raise exception using errcode = '22023', message = 'Payout cannot exceed the investor interest or principal due on the selected date.';
  end if;

  if p_interest_amount > 0 then
    insert into public.investor_transactions (
      investor_id, transaction_type, amount, transaction_date,
      payment_method, created_by
    )
    values (
      p_investor_id, 'interest_payout', p_interest_amount, p_paid_on,
      p_payment_method, auth.uid()
    );
  end if;

  if p_principal_amount > 0 then
    insert into public.investor_transactions (
      investor_id, transaction_type, amount, transaction_date,
      payment_method, created_by
    )
    values (
      p_investor_id, 'principal_payout', p_principal_amount, p_paid_on,
      p_payment_method, auth.uid()
    );
  end if;
end;
$$;

revoke all on function public.record_investor_payout(
  uuid,
  numeric,
  numeric,
  date,
  text
) from public;
grant execute on function public.record_investor_payout(
  uuid,
  numeric,
  numeric,
  date,
  text
) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'investors'
  ) then
    alter publication supabase_realtime add table public.investors;
  end if;
end
$$;
