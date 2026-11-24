begin;
create table if not exists kostora_private.portal_links (
 contract_id uuid primary key references public.rental_contracts(id),
 token uuid not null unique default gen_random_uuid(),
 expires_at timestamptz not null default (now()+interval '30 days')
);
create table if not exists kostora_private.complaint_photos (
 complaint_id uuid primary key references public.complaints(id) on delete cascade,
 image_data text not null check(length(image_data)<=2800000)
);
revoke all on all tables in schema kostora_private from public, anon, authenticated;
create or replace function public.kostora_portal_issue(p_contract uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.rental_contracts where id=p_contract and owner_id=auth.uid() and active and (end_date is null or end_date>=timezone('Asia/Makassar',now())::date)) then raise exception 'Kontrak tidak tersedia'; end if;
 insert into kostora_private.portal_links(contract_id) values(p_contract)
 on conflict(contract_id) do update set token=gen_random_uuid(),expires_at=now()+interval '30 days'
 returning token into v;
 return v;
end $$;
create or replace function public.kostora_portal_revoke(p_contract uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from kostora_private.portal_links l using public.rental_contracts c where l.contract_id=c.id and c.id=p_contract and c.owner_id=auth.uid();
end $$;
create or replace function kostora_private.portal_contract(p_token uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select c.id from kostora_private.portal_links l join public.rental_contracts c on c.id=l.contract_id
 where l.token=p_token and l.expires_at>now() and c.active and (c.end_date is null or c.end_date>=timezone('Asia/Makassar',now())::date)
$$;
create or replace function public.kostora_portal_read(p_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 cid:=kostora_private.portal_contract(p_token);
 if cid is null then raise exception 'Link tidak berlaku'; end if;
 return (select jsonb_build_object('property',p.name,'room',r.number,'tenant',t.name,
 'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'period',i.period_start,'due',i.due_date,'total',i.total,'paid',(select coalesce(sum(amount),0) from public.payments where invoice_id=i.id),'payments',coalesce((select jsonb_agg(jsonb_build_object('date',pay.paid_at,'amount',pay.amount,'method',pay.method) order by pay.paid_at) from public.payments pay where pay.invoice_id=i.id),'[]'::jsonb)) order by i.due_date desc) from public.invoices i where i.contract_id=cid),'[]'::jsonb),
 'complaints',coalesce((select jsonb_agg(jsonb_build_object('title',q.title,'description',q.description,'status',q.status,'date',q.created_at) order by q.created_at desc) from public.complaints q where q.contract_id=cid),'[]'::jsonb))
 from public.rental_contracts c join public.properties p on p.id=c.property_id join public.rooms r on r.id=c.room_id join public.tenants t on t.id=c.tenant_id where c.id=cid);
end $$;
create or replace function public.kostora_portal_complain(p_token uuid,p_title text,p_description text,p_photo text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; qid uuid;
begin
 cid:=kostora_private.portal_contract(p_token);
 if cid is null then raise exception 'Link tidak berlaku'; end if;
 if length(trim(coalesce(p_title,''))) not between 1 and 120 or length(trim(coalesce(p_description,''))) not between 1 and 2000 then raise exception 'Periksa isi keluhan'; end if;
 perform 1 from public.rental_contracts where id=cid for update;
 if (select count(*) from public.complaints where contract_id=cid and created_at>now()-interval '1 hour')>=5 then raise exception 'Batas laporan per jam tercapai'; end if;
 if p_photo is not null and (length(p_photo)>2800000 or p_photo !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$') then raise exception 'Foto tidak valid atau terlalu besar'; end if;
 insert into public.complaints(owner_id,property_id,contract_id,title,description) select owner_id,property_id,id,trim(p_title),trim(p_description) from public.rental_contracts where id=cid returning id into qid;
 if p_photo is not null then insert into kostora_private.complaint_photos values(qid,p_photo); end if;
 return qid;
end $$;
create or replace function public.kostora_complaint_photo(p_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select f.image_data from kostora_private.complaint_photos f join public.complaints q on q.id=f.complaint_id where q.id=p_id and q.owner_id=auth.uid()
$$;
revoke all on function kostora_private.portal_contract(uuid) from public,anon,authenticated;
revoke all on function public.kostora_portal_issue(uuid),public.kostora_portal_revoke(uuid),public.kostora_complaint_photo(uuid) from public,anon,authenticated;
grant execute on function public.kostora_portal_issue(uuid),public.kostora_portal_revoke(uuid),public.kostora_complaint_photo(uuid) to authenticated;
revoke all on function public.kostora_portal_read(uuid),public.kostora_portal_complain(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.kostora_portal_read(uuid),public.kostora_portal_complain(uuid,text,text,text) to anon,authenticated;
commit;