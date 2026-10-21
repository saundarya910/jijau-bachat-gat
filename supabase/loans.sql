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
  amount numeric(12, 2) not null,
  interest_paid numeric(12, 2) not null check (interest_paid >= 0),
  principal_paid numeric(12, 2) not null check (principal_paid >= 0),
  paid_on date not null,
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  constraint loan_repayment_amount_matches_allocation
    check (amount = interest_paid + principal_paid)
);

alter table public.loan_repayments
  drop constraint if exists loan_repayments_amount_check;
alter table public.loan_repayments
  drop constraint if exists loan_repayments_amount_nonnegative;
alter table public.loan_repayments
  add constraint loan_repayments_amount_nonnegative check (amount >= 0);

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

drop function if exists public.record_loan_repayment(uuid, numeric, date);

create or replace function public.record_loan_repayment(
  p_loan_id uuid,
  p_interest_paid numeric,
  p_principal_paid numeric,
  p_paid_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan record;
  v_latest_paid_on date;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true' then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_interest_paid is null
    or p_interest_paid < 0
    or p_interest_paid <> round(p_interest_paid, 2)
    or p_principal_paid is null
    or p_principal_paid < 0
    or p_principal_paid <> round(p_principal_paid, 2)
  then
    raise exception using errcode = '22023', message = 'Interest and principal repayment amounts must be non-negative and limited to paise precision.';
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
    p_interest_paid + p_principal_paid,
    p_interest_paid,
    p_principal_paid,
    p_paid_on,
    auth.uid()
  );
end;
$$;

revoke all on function public.record_loan_repayment(
  uuid,
  numeric,
  numeric,
  date
)
  from public;
grant execute on function public.record_loan_repayment(
  uuid,
  numeric,
  numeric,
  date
)
  to authenticated;

create or replace function public.edit_loan_repayment(
  p_repayment_id uuid,
  p_interest_paid numeric,
  p_principal_paid numeric,
  p_paid_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan_id uuid;
  v_loan record;
  v_created_at timestamptz;
  v_previous_paid_on date;
  v_next_paid_on date;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true' then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if p_interest_paid is null
    or p_interest_paid < 0
    or p_interest_paid <> round(p_interest_paid, 2)
    or p_principal_paid is null
    or p_principal_paid < 0
    or p_principal_paid <> round(p_principal_paid, 2)
  then
    raise exception using errcode = '22023', message = 'Interest and principal repayment amounts must be non-negative and limited to paise precision.';
  end if;

  select loan_id
  into v_loan_id
  from public.loan_repayments
  where id = p_repayment_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Repayment not found.';
  end if;

  select id, disbursed_on
  into v_loan
  from public.loans
  where id = v_loan_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Loan not found.';
  end if;

  select created_at
  into v_created_at
  from public.loan_repayments
  where id = p_repayment_id
    and loan_id = v_loan_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Repayment not found.';
  end if;

  if p_paid_on is null
    or p_paid_on > current_date
    or p_paid_on < v_loan.disbursed_on
  then
    raise exception using errcode = '22023', message = 'Payment date must be between the loan date and today.';
  end if;

  select max(paid_on)
  into v_previous_paid_on
  from public.loan_repayments
  where loan_id = v_loan_id
    and (created_at, id) < (v_created_at, p_repayment_id);

  select min(paid_on)
  into v_next_paid_on
  from public.loan_repayments
  where loan_id = v_loan_id
    and (created_at, id) > (v_created_at, p_repayment_id);

  if (v_previous_paid_on is not null and p_paid_on < v_previous_paid_on)
    or (v_next_paid_on is not null and p_paid_on > v_next_paid_on)
  then
    raise exception using errcode = '22023', message = 'Payment date must remain in the original repayment order.';
  end if;

  update public.loan_repayments
  set amount = p_interest_paid + p_principal_paid,
      interest_paid = p_interest_paid,
      principal_paid = p_principal_paid,
      paid_on = p_paid_on
  where id = p_repayment_id;
end;
$$;

create or replace function public.delete_loan_repayment(
  p_repayment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan_id uuid;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') <> 'true' then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  select loan_id
  into v_loan_id
  from public.loan_repayments
  where id = p_repayment_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Repayment not found.';
  end if;

  perform 1
  from public.loans
  where id = v_loan_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Loan not found.';
  end if;

  delete from public.loan_repayments
  where id = p_repayment_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Repayment not found.';
  end if;
end;
$$;

revoke all on function public.edit_loan_repayment(
  uuid,
  numeric,
  numeric,
  date
)
  from public;
grant execute on function public.edit_loan_repayment(
  uuid,
  numeric,
  numeric,
  date
)
  to authenticated;

revoke all on function public.delete_loan_repayment(uuid)
  from public;
grant execute on function public.delete_loan_repayment(uuid)
  to authenticated;
