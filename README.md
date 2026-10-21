# Jijau Women's Savings Group

## Supabase setup

The dashboard member total is read from the `public.members` table and updates
from Supabase Realtime when member records change. Open **सदस्य नोंदणी** to see
the roster and each member's savings history. Open **मासिक बचत** to check who
paid for a selected month, record a ₹500 payment, and enter its actual payment
date. Each member can have one payment record per contribution month.
Registration, payment history, and payment entry require an authenticated
admin account.

Loan tracking uses simple interest at 2% per calendar month on outstanding
principal. The first 2% charge applies on the loan date, with another charge
on the first day of each following calendar month; unpaid interest does not
itself accrue interest. The repayment form defaults interest to 2% of the
current remaining principal, with a separate principal amount. While principal
remains, at least one month's 2% interest remains due. Either amount can be
zero or exceed its displayed balance; the balance is clamped at zero, and
interest is waived once the full principal has been repaid. Run
[`supabase/loans.sql`](supabase/loans.sql) in the Supabase SQL Editor to enable
loan accounts and repayment history. Re-run it for the updated split-amount
repayment function, zero-amount repayments, and the admin-only repayment
edit/delete functions. The screen then shows open and repaid loans, balances,
and repayment allocations. “एकूण बाकी” is remaining principal (original loan
minus principal repaid); unpaid interest is shown separately and is not added
to that figure.

The **रोख व UPI व्यवहार** page records deposits and expenses by cash or UPI.
Run [`supabase/finance_transactions.sql`](supabase/finance_transactions.sql)
to create its admin-only ledger. The **अहवाल** page summarizes monthly savings,
loans issued, repayments, and outstanding loan balances from the saved records.

1. Create a Supabase project and run
   [`supabase/schema.sql`](supabase/schema.sql) in its SQL Editor. If you have
   already run the schema, run the additive
   [`supabase/monthly_savings.sql`](supabase/monthly_savings.sql),
   [`supabase/loans.sql`](supabase/loans.sql), and
   [`supabase/finance_transactions.sql`](supabase/finance_transactions.sql)
   migrations to create savings history, loans, repayment functions, and the
   finance transaction ledger.
2. Create the staff login account in the Supabase dashboard under
   **Authentication > Users**. Promote that account to an admin by running
   this in the SQL Editor, replacing the email:

   ```sql
   update auth.users
   set raw_app_meta_data =
     coalesce(raw_app_meta_data, '{}'::jsonb) || '{"is_admin": true}'::jsonb
   where email = 'saundaryasurwase910@gmail.com';
   ```

   Only users with this protected admin claim can read or register members.
   To add the 58 names from the provided roster, open
   [`supabase/import_members.sql`](supabase/import_members.sql), replace
   `YOUR_ADMIN_EMAIL` with that admin account's login email, and run the full
   script in the SQL Editor. It skips names already in `public.members`.
3. Copy the project URL and its publishable (or legacy anon) key from the
   Supabase project settings.
4. Start the app with those values:

   ```powershell
   flutter run -d chrome `
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
     --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_OR_LEGACY_ANON_KEY
   ```

   To build an Android release APK with the same configuration:

   ```powershell
   flutter build apk --release `
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
     --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_OR_LEGACY_ANON_KEY
   ```

   Do not use a Supabase `service_role` key in the Flutter app.

The app shows a setup message until both compile-time values are provided.
