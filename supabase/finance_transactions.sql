create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_type text not null
    check (transaction_type in ('deposit', 'expense')),
  payment_method text not null
    check (payment_method in ('cash', 'upi')),
  amount numeric(12, 2) not null check (amount > 0),
  description text check (description is null or length(description) <= 200),
  transaction_date date not null default current_date
    check (transaction_date <= current_date),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id)
);

create index if not exists finance_transactions_date_idx
  on public.finance_transactions(transaction_date desc, created_at desc);

alter table public.finance_transactions enable row level security;

drop policy if exists "Admins can read finance transactions"
  on public.finance_transactions;
create policy "Admins can read finance transactions"
  on public.finance_transactions for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true');

drop policy if exists "Admins can record finance transactions"
  on public.finance_transactions;
create policy "Admins can record finance transactions"
  on public.finance_transactions for insert to authenticated
  with check (
    (auth.jwt() -> 'app_metadata' ->> 'is_admin') = 'true'
    and auth.uid() = created_by
  );

grant select, insert on public.finance_transactions to authenticated;
