create table if not exists public.loans (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete restrict,
  principal numeric(12, 2) not null check (principal > 0),
  disbursed_on date not null,
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id)
);

create index if not exists loans_member_id_idx
  on public.loans(member_id);

create table if not exists public.loan_repayments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.loans(id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  interest_paid numeric(12, 2) not null check (interest_paid >= 0),
  principal_paid numeric(12, 2) not null check (principal_paid >= 0),
  paid_on date not null,
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  constraint loan_repayment_amount_matches_allocation
    check (amount = interest_paid + principal_paid)
);

create index if not exists loan_repayments_loan_id_idx
  on public.loan_repayments(loan_id, paid_on);

alter table public.loans enable row level security;
alter table public.loan_repayments enable row level security;

drop policy if exists "Admins can read loans" on public.loans;
create policy "Admins can read loans"
  on public.loans for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

drop policy if exists "Admins can create loans" on public.loans;
create policy "Admins can create loans"
  on public.loans for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true'
    and auth.uid() = created_by
  );

drop policy if exists "Admins can read loan repayments"
  on public.loan_repayments;
create policy "Admins can read loan repayments"
  on public.loan_repayments for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

grant select, insert on public.loans to authenticated;
grant select on public.loan_repayments to authenticated;

create or replace function public.record_loan_repayment(
  p_loan_id uuid,
  p_amount numeric,
  p_paid_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan record;
  v_month date;
  v_principal_paid_before_month numeric(12, 2);
  v_principal_paid numeric(12, 2);
  v_interest_paid numeric(12, 2);
  v_accrued_interest numeric(12, 2) := 0;
  v_interest_due numeric(12, 2);
  v_principal_due numeric(12, 2);
  v_interest_component numeric(12, 2);
  v_principal_component numeric(12, 2);
  v_latest_paid_on date;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true' then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception using errcode = '22023', message = 'Repayment amount must be positive and limited to paise precision.';
  end if;

  if p_paid_on is null or p_paid_on > current_date then
    raise exception using errcode = '22023', message = 'Payment date cannot be in the future.';
  end if;

  select id, member_id, principal, disbursed_on
  into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Loan not found.';
  end if;

  if p_paid_on < v_loan.disbursed_on then
    raise exception using errcode = '22023', message = 'Payment date cannot be before the loan date.';
  end if;

  select max(paid_on)
  into v_latest_paid_on
  from public.loan_repayments
  where loan_id = p_loan_id;

  if v_latest_paid_on is not null and p_paid_on < v_latest_paid_on then
    raise exception using errcode = '22023', message = 'Record repayments in payment-date order.';
  end if;

  for v_month in
    select series.month_start::date
    from pg_catalog.generate_series(
      (pg_catalog.date_trunc('month', v_loan.disbursed_on)::date
        + interval '1 month'),
      pg_catalog.date_trunc('month', p_paid_on)::date,
      interval '1 month'
    ) as series(month_start)
  loop
    select coalesce(sum(principal_paid), 0)
    into v_principal_paid_before_month
    from public.loan_repayments
    where loan_id = p_loan_id
      and paid_on < v_month;

    v_accrued_interest := v_accrued_interest
    + round(
        greatest(v_loan.principal - v_principal_paid_before_month, 0)
            * 0.02,
          2
        );
  end loop;

  select
    coalesce(sum(principal_paid), 0),
    coalesce(sum(interest_paid), 0)
  into v_principal_paid, v_interest_paid
  from public.loan_repayments
  where loan_id = p_loan_id;

  v_principal_due := greatest(
    v_loan.principal - v_principal_paid,
    0
  );
  v_interest_due := greatest(
    v_accrued_interest - v_interest_paid,
    0
  );

  if v_principal_due = 0 then
    v_interest_due := 0;
  end if;

  if p_amount > v_principal_due + v_interest_due then
    raise exception using errcode = '22023', message = 'Repayment exceeds the outstanding loan balance.';
  end if;

  v_interest_component := least(p_amount, v_interest_due);
  v_principal_component := p_amount - v_interest_component;

  insert into public.loan_repayments (
    loan_id,
    amount,
    interest_paid,
    principal_paid,
    paid_on,
    created_by
  )
  values (
    p_loan_id,
    p_amount,
    v_interest_component,
    v_principal_component,
    p_paid_on,
    auth.uid()
  );
end;
$$;

revoke all on function public.record_loan_repayment(uuid, numeric, date)
  from public;
grant execute on function public.record_loan_repayment(uuid, numeric, date)
  to authenticated;
