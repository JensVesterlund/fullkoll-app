-- Base schema for Full Koll – Supabase (Postgres)
-- This file creates core tables used by the app and expected by the
-- Supabase repositories in lib/services/repositories/*.
--
-- NOTE:
-- - All primary keys are UUID.
-- - Column names use snake_case to match the repos.
-- - Defaults are provided where sensible; repos also set explicit values.

-- Ensure required schemas are present
create schema if not exists public;

-- 1) Application users table (metadata) with FK to auth.users
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  email_verified boolean not null default false,
  created_at timestamptz not null default now(),
  last_login_at timestamptz not null default now(),
  locale text not null default 'sv-SE',
  currency text not null default 'SEK',
  reminder_defaults_before_expiry text not null default '30,7',
  reminder_defaults_before_charge text not null default '14,1',
  notification_prefs_push boolean not null default true,
  notification_prefs_email boolean not null default false,
  notification_prefs_muted boolean not null default false,
  role text not null default 'user',
  privacy_accepted_at timestamptz,
  privacy_version int not null default 1,
  do_not_track boolean not null default false
);
create index if not exists idx_users_email on public.users (email);

-- 2) Budgets and related entities (created first so all FKs can reference them)
create table if not exists public.budgets (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  year int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_budgets_owner on public.budgets (owner_id);
create index if not exists idx_budgets_year on public.budgets (year);

create table if not exists public.budget_categories (
  id uuid primary key,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  name text not null,
  monthly_limit numeric not null
);

-- Backfill: rename legacy column "limit" -> "monthly_limit" if old column still exists
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'budget_categories'
      and column_name = 'limit'
  ) then
    alter table public.budget_categories rename column "limit" to monthly_limit;
  end if;
exception when undefined_table then
  -- Table does not exist yet; no-op
  null;
end $$;

-- Ensure column budget_id exists even if table was created earlier without it
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='budget_categories'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_categories' and column_name='budget_id'
  ) then
    alter table public.budget_categories add column budget_id uuid;
  end if;
end $$;

-- Ensure FK constraint from budget_categories.budget_id -> budgets.id exists
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_categories' and column_name='budget_id'
  ) and not exists (
    select 1
    from information_schema.table_constraints tc
    where tc.table_schema='public'
      and tc.table_name='budget_categories'
      and tc.constraint_type='FOREIGN KEY'
      and tc.constraint_name='budget_categories_budget_id_fkey'
  ) then
    alter table public.budget_categories
      add constraint budget_categories_budget_id_fkey
      foreign key (budget_id) references public.budgets(id) on delete cascade;
  end if;
end $$;

-- Create index after ensuring column exists
create index if not exists idx_budget_categories_budget on public.budget_categories (budget_id);

create table if not exists public.budget_transactions (
  id uuid primary key,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  category_id uuid references public.budget_categories(id) on delete set null,
  type text not null,
  description text,
  amount numeric not null,
  date timestamptz not null
);

-- Ensure columns exist when table pre-exists with older schema
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='budget_transactions'
  ) then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='budget_transactions' and column_name='budget_id'
    ) then
      alter table public.budget_transactions add column budget_id uuid;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='budget_transactions' and column_name='category_id'
    ) then
      alter table public.budget_transactions add column category_id uuid;
    end if;
    -- ensure the timestamp column "date" exists (older schemas may lack it)
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='budget_transactions' and column_name='date'
    ) then
      alter table public.budget_transactions add column "date" timestamptz not null default now();
    end if;
  end if;
end $$;

-- Ensure FK constraints for budget_transactions
do $$
begin
  -- FK to budgets
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_transactions' and column_name='budget_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc
    where tc.table_schema='public' and tc.table_name='budget_transactions' and tc.constraint_name='budget_transactions_budget_id_fkey'
  ) then
    alter table public.budget_transactions
      add constraint budget_transactions_budget_id_fkey
      foreign key (budget_id) references public.budgets(id) on delete cascade;
  end if;

  -- FK to budget_categories
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_transactions' and column_name='category_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc
    where tc.table_schema='public' and tc.table_name='budget_transactions' and tc.constraint_name='budget_transactions_category_id_fkey'
  ) then
    alter table public.budget_transactions
      add constraint budget_transactions_category_id_fkey
      foreign key (category_id) references public.budget_categories(id) on delete set null;
  end if;
end $$;

-- Create indexes after ensuring columns exist
create index if not exists idx_budget_tx_budget on public.budget_transactions (budget_id);
create index if not exists idx_budget_tx_date on public.budget_transactions (date);

-- Optional incomes per budget
create table if not exists public.budget_incomes (
  id uuid primary key,
  budget_id uuid not null references public.budgets(id) on delete cascade,
  description text not null default '',
  amount numeric not null,
  frequency text not null default 'monthly', -- 'monthly' | 'yearly'
  created_at timestamptz not null default now()
);

-- Ensure budget_id exists for budget_incomes on older schemas
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='budget_incomes'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_incomes' and column_name='budget_id'
  ) then
    alter table public.budget_incomes add column budget_id uuid;
  end if;
end $$;

-- Ensure FK for budget_incomes.budget_id
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='budget_incomes' and column_name='budget_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc
    where tc.table_schema='public' and tc.table_name='budget_incomes' and tc.constraint_name='budget_incomes_budget_id_fkey'
  ) then
    alter table public.budget_incomes
      add constraint budget_incomes_budget_id_fkey
      foreign key (budget_id) references public.budgets(id) on delete cascade;
  end if;
end $$;

-- Create index after ensuring column exists
create index if not exists idx_budget_incomes_budget on public.budget_incomes (budget_id);

-- 3) Receipts (after budgets so optional FKs can be added safely)
create table if not exists public.receipts (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  store text not null,
  purchased_at timestamptz,
  amount numeric not null,
  currency text not null default 'SEK',
  category text,
  return_deadline timestamptz,
  exchange_deadline timestamptz,
  warranty_expires timestamptz,
  refund_deadline timestamptz,
  reminders_enabled boolean not null default false,
  reminder1_at timestamptz,
  reminder2_at timestamptz,
  reminder_jobs jsonb,
  notes text,
  image_url text,
  archived boolean not null default false,
  budget_id uuid references public.budgets(id) on delete set null,
  budget_category_id uuid references public.budget_categories(id) on delete set null,
  budget_transaction_id uuid references public.budget_transactions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_receipts_owner on public.receipts (owner_id);
create index if not exists idx_receipts_purchased_at on public.receipts (purchased_at);

-- Ensure optional budget columns exist for receipts when table already exists
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='receipts'
  ) then
    if not exists (
      select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_id'
    ) then
      alter table public.receipts add column budget_id uuid;
    end if;
    if not exists (
      select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_category_id'
    ) then
      alter table public.receipts add column budget_category_id uuid;
    end if;
    if not exists (
      select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_transaction_id'
    ) then
      alter table public.receipts add column budget_transaction_id uuid;
    end if;
  end if;
end $$;

-- Ensure FKs for receipts' optional budget columns
do $$
begin
  if exists (
    select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc where tc.table_schema='public' and tc.table_name='receipts' and tc.constraint_name='receipts_budget_id_fkey'
  ) then
    alter table public.receipts add constraint receipts_budget_id_fkey foreign key (budget_id) references public.budgets(id) on delete set null;
  end if;

  if exists (
    select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_category_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc where tc.table_schema='public' and tc.table_name='receipts' and tc.constraint_name='receipts_budget_category_id_fkey'
  ) then
    alter table public.receipts add constraint receipts_budget_category_id_fkey foreign key (budget_category_id) references public.budget_categories(id) on delete set null;
  end if;

  if exists (
    select 1 from information_schema.columns where table_schema='public' and table_name='receipts' and column_name='budget_transaction_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc where tc.table_schema='public' and tc.table_name='receipts' and tc.constraint_name='receipts_budget_transaction_id_fkey'
  ) then
    alter table public.receipts add constraint receipts_budget_transaction_id_fkey foreign key (budget_transaction_id) references public.budget_transactions(id) on delete set null;
  end if;
end $$;

-- 4) Gift cards
create table if not exists public.gift_cards (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  brand text not null,
  category text,
  purchase_at timestamptz,
  expires_at timestamptz,
  card_number text,
  pin text,
  initial_balance numeric not null,
  current_balance numeric not null,
  currency text not null default 'SEK',
  status text not null default 'active',
  notes text,
  image_url text,
  reminders_enabled boolean not null default false,
  reminder1_at timestamptz,
  reminder2_at timestamptz,
  reminder_job_ids text[],
  documents jsonb default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_gift_cards_owner on public.gift_cards (owner_id);
create index if not exists idx_gift_cards_expires on public.gift_cards (expires_at);

-- 5) Subscriptions (Autogiro)
create table if not exists public.subscriptions (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  service_name text not null,
  category text,
  amount_per_period numeric not null,
  currency text not null default 'SEK',
  billing_interval text not null,
  payment_method text not null,
  next_charge_at timestamptz not null,
  start_date timestamptz not null,
  binding_months int,
  trial_enabled boolean not null default false,
  trial_ends_at timestamptz,
  trial_price numeric,
  reminder_before_charge_days text not null default '14,1',
  reminder_on_trial_end boolean not null default true,
  budget_category_id uuid references public.budget_categories(id) on delete set null,
  notes text,
  portal_url text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_subscriptions_owner on public.subscriptions (owner_id);
create index if not exists idx_subscriptions_next_charge on public.subscriptions (next_charge_at);

-- Ensure optional budget_category_id exists for subscriptions on older schemas
do $$
begin
  if exists (
    select 1 from information_schema.tables where table_schema='public' and table_name='subscriptions'
  ) and not exists (
    select 1 from information_schema.columns where table_schema='public' and table_name='subscriptions' and column_name='budget_category_id'
  ) then
    alter table public.subscriptions add column budget_category_id uuid;
  end if;
end $$;

-- Ensure FK for subscriptions.budget_category_id
do $$
begin
  if exists (
    select 1 from information_schema.columns where table_schema='public' and table_name='subscriptions' and column_name='budget_category_id'
  ) and not exists (
    select 1 from information_schema.table_constraints tc where tc.table_schema='public' and tc.table_name='subscriptions' and tc.constraint_name='subscriptions_budget_category_id_fkey'
  ) then
    alter table public.subscriptions add constraint subscriptions_budget_category_id_fkey foreign key (budget_category_id) references public.budget_categories(id) on delete set null;
  end if;
end $$;

-- 6) Cost Split (groups, participants, expenses, settlements)
create table if not exists public.split_groups (
  id uuid primary key,
  title text not null,
  creator_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default now()
);
-- Ensure creator_id exists on older schemas of split_groups and add FK if missing
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='split_groups'
  ) then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='split_groups' and column_name='creator_id'
    ) then
      alter table public.split_groups add column creator_id uuid;
    end if;

    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='split_groups' and column_name='creator_id'
    ) and not exists (
      select 1 from information_schema.table_constraints tc
      where tc.table_schema='public' and tc.table_name='split_groups' and tc.constraint_name='split_groups_creator_id_fkey'
    ) then
      alter table public.split_groups
        add constraint split_groups_creator_id_fkey
        foreign key (creator_id) references auth.users(id) on delete cascade;
    end if;
  end if;
end $$;
create index if not exists idx_split_groups_creator on public.split_groups (creator_id);

create table if not exists public.participants (
  id uuid primary key,
  split_group_id uuid not null references public.split_groups(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  contact text,
  balance numeric not null default 0
);
create index if not exists idx_participants_group on public.participants (split_group_id);

create table if not exists public.expenses (
  id uuid primary key,
  split_group_id uuid not null references public.split_groups(id) on delete cascade,
  paid_by uuid references public.participants(id) on delete set null,
  description text,
  amount numeric not null,
  shared_with uuid[] not null,
  receipt_url text,
  created_at timestamptz not null default now()
);
create index if not exists idx_expenses_group on public.expenses (split_group_id);
create index if not exists idx_expenses_created on public.expenses (created_at);

create table if not exists public.settlements (
  id uuid primary key,
  split_group_id uuid not null references public.split_groups(id) on delete cascade,
  payer_id uuid not null references public.participants(id) on delete cascade,
  receiver_id uuid not null references public.participants(id) on delete cascade,
  amount numeric not null,
  status text not null default 'pending',
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  reminder_job_id text
);
create index if not exists idx_settlements_group on public.settlements (split_group_id);

-- 7) Storage buckets (receipts, giftcards, splits, documents)
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('giftcards', 'giftcards', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('splits', 'splits', true)
on conflict (id) do nothing;

-- documents: used by giftcards_screen.dart
insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do nothing;
