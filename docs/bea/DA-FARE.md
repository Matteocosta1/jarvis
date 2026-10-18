# Reparto Bea — da fare insieme a Bea

Quando Alessandro sarà con Bea e avrà il suo iPhone:

1. Segreto `BEA_SOS_CHIAVE` su Supabase (Discosizer Serate → Edge Functions → Secrets).
2. Sul telefono di Bea: Comando rapido «Aiuto Ale» (posizione → POST a `jarvis-bea-sos` con `x-bea-chiave`, `lat`, `lon` → messaggio «Ho bisogno di te» + posizione), collegato al tasto Azione (o «Ehi Siri, Aiuto Ale»).
3. Prova con il campo `prova: true`, poi toglierlo. Dare tutti i permessi «Consenti sempre».
4. Xcode: capacità **Time Sensitive Notifications** sul target Untitled Project.

Poi aggiungere nell'app (dal mockup `bea-protezione-mockup.png`):
- la mappetta con il punto di Bea nella schermata rossa «Bea ha bisogno di lei»;
- il riquadro «Tocco d'aiuto» nella sezione «La sua sicurezza».
