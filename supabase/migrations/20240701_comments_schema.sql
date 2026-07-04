-- ================================================================
-- Comments and Comment Likes Schema
-- Safe to re-run — uses IF NOT EXISTS / IF NOT EXISTS everywhere
-- ================================================================

-- ── Add missing columns to existing comments table ────────────
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS parent_comment_id uuid references public.comments(id) on delete cascade,
  ADD COLUMN IF NOT EXISTS likes_count integer not null default 0,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

-- ── Create comment_likes table ────────────────────────────────
create table if not exists public.comment_likes (
  comment_id  uuid not null references public.comments(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- ── Indexes ───────────────────────────────────────────────────
create index if not exists idx_comments_post_id  on public.comments(post_id);
create index if not exists idx_comments_parent   on public.comments(parent_comment_id);
create index if not exists idx_comments_user_id  on public.comments(user_id);
create index if not exists idx_comment_likes_comment on public.comment_likes(comment_id);

-- ── RLS ───────────────────────────────────────────────────────
alter table public.comments      enable row level security;
alter table public.comment_likes enable row level security;

-- Comments policies
do $$ begin
  create policy "Comments are viewable by all"
    on public.comments for select using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Authenticated users can comment"
    on public.comments for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Users can update own comments"
    on public.comments for update using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Users can delete own comments"
    on public.comments for delete using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

-- Comment likes policies
do $$ begin
  create policy "Comment likes are viewable by all"
    on public.comment_likes for select using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Authenticated users can like comments"
    on public.comment_likes for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Users can unlike comments"
    on public.comment_likes for delete using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

-- ── Trigger: sync likes_count ─────────────────────────────────
create or replace function public.update_comment_likes_count()
returns trigger language plpgsql security definer as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set likes_count = likes_count + 1
    where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.comments set likes_count = greatest(likes_count - 1, 0)
    where id = old.comment_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_comment_likes_count on public.comment_likes;
create trigger trg_comment_likes_count
  after insert or delete on public.comment_likes
  for each row execute function public.update_comment_likes_count();

-- ── Trigger: sync post comments_count ────────────────────────
create or replace function public.update_post_comments_count()
returns trigger language plpgsql security definer as $$
begin
  if tg_op = 'INSERT' and new.parent_comment_id is null then
    update public.posts set comments_count = comments_count + 1
    where id = new.post_id;
  elsif tg_op = 'DELETE' and old.parent_comment_id is null then
    update public.posts set comments_count = greatest(comments_count - 1, 0)
    where id = old.post_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_post_comments_count on public.comments;
create trigger trg_post_comments_count
  after insert or delete on public.comments
  for each row execute function public.update_post_comments_count();

-- ── updated_at trigger ────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_comments_updated_at on public.comments;
create trigger trg_comments_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- ── Enable Realtime ───────────────────────────────────────────
do $$
begin
  begin
    alter publication supabase_realtime add table public.comments;
  exception when others then null;
  end;
end;
$$;
