begin;
-- Generate at H-7, including missed cycles for active contracts.
create schema if not exists kostora_private;
revoke all on schema kostora_private from public, anon, authenticated;
create or replace function kostora_private.generate_invoices(p_owner uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare n bigint;
begin
 insert into public.invoices(owner_id,property_id,contract_id,period_start,due_date,total)
 select c.owner_id,c.property_id,c.id,d.due,d.due,c.monthly_rent
 from public.rental_contracts c
 cross join lateral generate_series(0, greatest(0,
 (extract(year from age((timezone('Asia/Makassar',now())::date+7),c.first_due_date))::int*12+
 extract(month from age((timezone('Asia/Makassar',now())::date+7),c.first_due_date))::int)+1)) g(i)
 cross join lateral (select (c.first_due_date+make_interval(months=>g.i))::date as due) d
 where c.active and (p_owner is null or c.owner_id=p_owner)
 and d.due<=timezone('Asia/Makassar',now())::date+7
 and (c.end_date is null or d.due<=c.end_date)
 on conflict(contract_id,period_start) do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function kostora_private.generate_invoices(uuid) from public,anon,authenticated;
create or replace function public.kostora_generate_invoices()
returns bigint language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 return kostora_private.generate_invoices(auth.uid());
end $$;
revoke all on function public.kostora_generate_invoices() from public,anon;
grant execute on function public.kostora_generate_invoices() to authenticated;
-- Invoice records cannot be edited or deleted by browser clients.
revoke insert,update,delete on public.invoices from authenticated;
-- Existing payment trigger needs permission to lock invoices after revoking update.
alter function public.validate_payment() security definer;
revoke all on function public.validate_payment() from public,anon,authenticated;
commit;
