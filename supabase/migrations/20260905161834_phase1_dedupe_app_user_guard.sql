-- Remove the redundant second guard trigger on app_users.
--
-- nodex.tg_app_users_guard_admin_fields already covers every authenticated
-- update path (not just self-updates) and is the stricter of the two. Keeping
-- both would run the same freeze logic twice per statement.

drop trigger if exists app_users_self_update_guard on public.app_users;
drop function if exists nodex.tg_app_user_self_update_guard();
