-- Row-Level Security policies for Full Koll tables and Storage

-- Enable RLS
alter table if exists public.users enable row level security;
alter table if exists public.receipts enable row level security;
alter table if exists public.gift_cards enable row level security;
alter table if exists public.budgets enable row level security;
alter table if exists public.budget_categories enable row level security;
alter table if exists public.budget_transactions enable row level security;
alter table if exists public.subscriptions enable row level security;
alter table if exists public.split_groups enable row level security;
alter table if exists public.participants enable row level security;
alter table if exists public.expenses enable row level security;
alter table if exists public.settlements enable row level security;

-- USERS: allow self access; allow insert/update with CHECK(true) as required
drop policy if exists users_select_self on public.users;
create policy users_select_self on public.users
  for select to authenticated
  using (id = auth.uid());

drop policy if exists users_insert_any on public.users;
create policy users_insert_any on public.users
  for insert to authenticated
  with check (true);

drop policy if exists users_update_any on public.users;
create policy users_update_any on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (true);

drop policy if exists users_delete_self on public.users;
create policy users_delete_self on public.users
  for delete to authenticated
  using (id = auth.uid());

-- RECEIPTS: owner-based
drop policy if exists receipts_all_owner on public.receipts;
create policy receipts_all_owner on public.receipts
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- GIFT CARDS: owner-based
drop policy if exists gift_cards_all_owner on public.gift_cards;
create policy gift_cards_all_owner on public.gift_cards
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- BUDGETS: owner-based
drop policy if exists budgets_all_owner on public.budgets;
create policy budgets_all_owner on public.budgets
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- BUDGET CATEGORIES: through budget ownership
drop policy if exists budget_categories_all_owner on public.budget_categories;
create policy budget_categories_all_owner on public.budget_categories
  for all to authenticated
  using (exists (
    select 1 from public.budgets b where b.id = budget_id and b.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.budgets b where b.id = budget_id and b.owner_id = auth.uid()
  ));

-- BUDGET TRANSACTIONS: through budget ownership
drop policy if exists budget_transactions_all_owner on public.budget_transactions;
create policy budget_transactions_all_owner on public.budget_transactions
  for all to authenticated
  using (exists (
    select 1 from public.budgets b where b.id = budget_id and b.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.budgets b where b.id = budget_id and b.owner_id = auth.uid()
  ));

-- SUBSCRIPTIONS: owner-based
drop policy if exists subscriptions_all_owner on public.subscriptions;
create policy subscriptions_all_owner on public.subscriptions
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- SPLIT GROUPS: creator-based
drop policy if exists split_groups_all_creator on public.split_groups;
create policy split_groups_all_creator on public.split_groups
  for all to authenticated
  using (creator_id = auth.uid())
  with check (creator_id = auth.uid());

-- PARTICIPANTS: allow for groups created by user
drop policy if exists participants_all_group_creator on public.participants;
create policy participants_all_group_creator on public.participants
  for all to authenticated
  using (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ));

-- EXPENSES: allow for groups created by user
drop policy if exists expenses_all_group_creator on public.expenses;
create policy expenses_all_group_creator on public.expenses
  for all to authenticated
  using (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ));

-- SETTLEMENTS: allow for groups created by user
drop policy if exists settlements_all_group_creator on public.settlements;
create policy settlements_all_group_creator on public.settlements
  for all to authenticated
  using (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.split_groups g where g.id = split_group_id and g.creator_id = auth.uid()
  ));

-- STORAGE POLICIES: require path prefix = auth.uid()/
-- Receipts bucket
drop policy if exists "receipts_read_own" on storage.objects;
create policy "receipts_read_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts' and name like (auth.uid()::text || '/%'));

drop policy if exists "receipts_write_own" on storage.objects;
create policy "receipts_write_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts' and name like (auth.uid()::text || '/%'));

drop policy if exists "receipts_update_own" on storage.objects;
create policy "receipts_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'receipts' and name like (auth.uid()::text || '/%'))
  with check (bucket_id = 'receipts' and name like (auth.uid()::text || '/%'));

drop policy if exists "receipts_delete_own" on storage.objects;
create policy "receipts_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'receipts' and name like (auth.uid()::text || '/%'));

-- Giftcards bucket
drop policy if exists "giftcards_read_own" on storage.objects;
create policy "giftcards_read_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'giftcards' and name like (auth.uid()::text || '/%'));

drop policy if exists "giftcards_write_own" on storage.objects;
create policy "giftcards_write_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'giftcards' and name like (auth.uid()::text || '/%'));

drop policy if exists "giftcards_update_own" on storage.objects;
create policy "giftcards_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'giftcards' and name like (auth.uid()::text || '/%'))
  with check (bucket_id = 'giftcards' and name like (auth.uid()::text || '/%'));

drop policy if exists "giftcards_delete_own" on storage.objects;
create policy "giftcards_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'giftcards' and name like (auth.uid()::text || '/%'));

-- Splits bucket
drop policy if exists "splits_read_own" on storage.objects;
create policy "splits_read_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'splits' and name like (auth.uid()::text || '/%'));

drop policy if exists "splits_write_own" on storage.objects;
create policy "splits_write_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'splits' and name like (auth.uid()::text || '/%'));

drop policy if exists "splits_update_own" on storage.objects;
create policy "splits_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'splits' and name like (auth.uid()::text || '/%'))
  with check (bucket_id = 'splits' and name like (auth.uid()::text || '/%'));

drop policy if exists "splits_delete_own" on storage.objects;
create policy "splits_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'splits' and name like (auth.uid()::text || '/%'));

-- Documents bucket (used by giftcards documents)
drop policy if exists "documents_read_own" on storage.objects;
create policy "documents_read_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'documents' and name like (auth.uid()::text || '/%'));

drop policy if exists "documents_write_own" on storage.objects;
create policy "documents_write_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents' and name like (auth.uid()::text || '/%'));

drop policy if exists "documents_update_own" on storage.objects;
create policy "documents_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'documents' and name like (auth.uid()::text || '/%'))
  with check (bucket_id = 'documents' and name like (auth.uid()::text || '/%'));

drop policy if exists "documents_delete_own" on storage.objects;
create policy "documents_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documents' and name like (auth.uid()::text || '/%'));
