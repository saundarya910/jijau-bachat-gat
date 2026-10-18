begin;

do $$
declare
  admin_id uuid;
  inserted_count integer;
begin
  select id
  into admin_id
  from auth.users
  where lower(email) = lower('YOUR_ADMIN_EMAIL')
    and raw_app_meta_data ->> 'is_admin' = 'true';

  if admin_id is null then
    raise exception
      'Admin account not found. Replace YOUR_ADMIN_EMAIL with the admin login email.';
  end if;

  insert into public.members (name, created_by)
  select incoming.name, admin_id
  from (
    values
      ('सौंदर्या सुरवसे'),
      ('अंजली पाटील'),
      ('प्रगती शिंदे'),
      ('महानंदा पाटील'),
      ('वैष्णवी पाटील'),
      ('रजनी पाटील'),
      ('मंगल सुरवसे'),
      ('सुरेखा सुरवसे'),
      ('शैला सुरवसे'),
      ('श्रुती सुरवसे'),
      ('विश्वजीत सुरवसे'),
      ('सोनाली तांबे'),
      ('कलावती सुरवसे'),
      ('हर्षद सुरवसे'),
      ('अरुणा सुरवसे'),
      ('मिनाक्षी मोहिते'),
      ('सुवर्णा कुलकर्णी'),
      ('शकुंतला क्षीरसागर'),
      ('कमल तांबे'),
      ('शांता कांबळे'),
      ('राजश्री नागाटिळक'),
      ('पार्वती नागटिळक'),
      ('सुमन दुगाने'),
      ('सुनिता करंजकर'),
      ('शालिनी ढेकणे'),
      ('सानिका ढेकणे'),
      ('रमा दीक्षित'),
      ('वैष्णवी दीक्षित'),
      ('सुवर्णा शिराळ'),
      ('पिंकू बेलोरे'),
      ('महादेवी नाईकवाडी'),
      ('शुभम नाईकवाडी'),
      ('ललिता भोसले'),
      ('स्वाती भोसले'),
      ('साक्षी बाबर'),
      ('सिंधू सुरवसे'),
      ('छाया गायकवाड'),
      ('आश्विनी भोंडे'),
      ('ऋतुजा सरडे'),
      ('स्वाती सरडे'),
      ('सरिता सरडे'),
      ('अनुराधा बळे'),
      ('पूजा बळे'),
      ('महानंदा तावसकर'),
      ('मानिषा हिसवणकर'),
      ('निर्मला दुगाने'),
      ('माही लांबाते'),
      ('योगिता लांडगे'),
      ('लता भालेराव'),
      ('श्रुती तट'),
      ('सीमा क्षीरसागर'),
      ('प्रियनीता वाघमारे'),
      ('शारदा दुर्वे'),
      ('वैशाली ढेकणे'),
      ('अपेक्षा ढेकणे'),
      ('रोहिणी ढेकणे'),
      ('शालिनी कदम'),
      ('श्रुती डुबे'),
      ('विजया बेंदर'),
      ('पूजा जाधवर'),
      ('स्नेहल कुलकर्णी'),
      ('यशोदा समिंदर'),
      ('दिशा कदम'),
      ('स्वाती कोरे'),
      ('रोहिणी शेंडगे'),
      ('धनश्री पाटील')
  ) as incoming(name)
  where not exists (
    select 1
    from public.members as existing
    where existing.name = incoming.name
  );

  get diagnostics inserted_count = row_count;
  raise notice 'Imported % new members; existing matching names were skipped.',
    inserted_count;
end
$$;

commit;
