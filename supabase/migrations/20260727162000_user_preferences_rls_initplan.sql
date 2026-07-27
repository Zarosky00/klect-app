-- Keep auth.uid() stable per statement so preference policies scale with
-- account volume instead of re-evaluating the JWT helper for every row.

drop policy if exists user_preferences_select_own
  on public.user_preferences;
create policy user_preferences_select_own
  on public.user_preferences
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_preferences_insert_own
  on public.user_preferences;
create policy user_preferences_insert_own
  on public.user_preferences
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_preferences_update_own
  on public.user_preferences;
create policy user_preferences_update_own
  on public.user_preferences
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
