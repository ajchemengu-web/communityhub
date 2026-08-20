-- ============================================================
-- posts write-policy ownership fix (INSERT/UPDATE/DELETE)
-- ============================================================
-- posts_update/posts_delete were `qual = true` with no author_id
-- check at all -- confirmed live -- meaning any authenticated user
-- could update or delete ANY other user's post via a direct API
-- call, not just their own. posts_insert similarly had no author_id
-- check (only the channel-membership condition added by
-- 20260818c_posts_channel_scoping.sql), letting a client insert a
-- post row attributed to someone else's author_id.
--
-- None of posts' INSERT/UPDATE/DELETE policies are defined in any
-- tracked migration (posts' own DDL was created directly in
-- Supabase Studio, same situation already flagged in
-- 20260706b_posts_users_rls_privacy_blocking.sql for its SELECT
-- policy) -- these are dropped and recreated by their live names,
-- verified via pg_policies immediately before writing this file:
--   posts_insert (INSERT): with_check =
--     (channel_id is null) or (is_group_member(channel_id) and
--     exists (select 1 from community_channels ch where ch.id =
--     posts.channel_id and ch.community_id = posts.community_id))
--   posts_update (UPDATE): qual = true, with_check = null
--   posts_delete (DELETE): qual = true
--
-- posts_insert's existing channel-membership condition is preserved
-- verbatim below, with author_id = auth.uid() ANDed in.
--
-- Safe to run multiple times.
-- ============================================================

begin;

drop policy if exists "posts_insert" on public.posts;
create policy "posts_insert" on public.posts
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and (
      channel_id is null
      or (
        is_group_member(channel_id)
        and exists (
          select 1 from public.community_channels ch
          where ch.id = channel_id and ch.community_id = posts.community_id
        )
      )
    )
  );

drop policy if exists "posts_update" on public.posts;
create policy "posts_update" on public.posts
  for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists "posts_delete" on public.posts;
create policy "posts_delete" on public.posts
  for delete to authenticated
  using (author_id = auth.uid());

commit;
