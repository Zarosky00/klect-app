-- `subcollection_has_content` is only called from SECURITY DEFINER code
-- (`can_view_entity`, `get_closeup`), which runs as the function owner, so the
-- API roles do not need to call it directly. `collection_has_content` keeps
-- EXECUTE because the `collections_read` policy evaluates it as the caller.
revoke execute on function public.subcollection_has_content(uuid)
  from anon, authenticated;
