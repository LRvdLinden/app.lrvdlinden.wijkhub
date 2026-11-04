# WijkHub

Alles van je wijk, op één plek. WijkHub brengt de WhatsApp-groepen van een wijk samen in één app: buurtchat, weggeefhoek, marktplaats, ondernemershoek en buurtpreventie, met profielen, berichten met foto's, reacties en likes.

- **Bundle ID:** `app.lrvdlinden.wijkhub` · versie 1.0.0 (1) · team `EU3UY476T6`
- **Platforms:** iPhone, iPad en Mac (Mac Catalyst) · iOS 17+ / macOS 14+ · Android volgt in fase 4
- **Backend:** Supabase (database, inloggen, foto-opslag)
- **Talen:** Nederlands, Engels, Duits, Frans, Spaans, Italiaans, Zweeds, Noors, Deens, Pools
- **Website / juridisch:** https://wijk-hub.nl (`/privacy`, `/support`, `/voorwaarden`)

## Fase 1 (deze versie)

- Geanimeerd startscherm, inloggen met e-mailcode of Inloggen met Apple
- Onboarding: naam + profielfoto, optioneel 06-nummer (zelf kiezen of buren het zien), wijk kiezen, huisregels
- Tijdlijn van de wijk en per groep, nieuwe berichten met max. 4 foto's, reacties, likes, delen
- Buurtpreventie met vaste melding "Bij nood eerst 112"
- Profielen, eigen profiel wijzigen, bellen/WhatsApp als het nummer zichtbaar is
- Melden en blokkeren; beheerders kunnen berichten verbergen en meldingen afhandelen
- Face ID-vergrendeling, weergave Automatisch/Licht/Donker, account verwijderen
- Vaste onderdelen: privacy manifest, MoreAppsCard, app-info-footer, review-prompt

Volgende fases: marktplaats met verkocht zetten, diensten/hulp, privéberichten (2) · evenementen, ondernemers met goedkeuring, preventiemeldingen (3) · push, widgets, Siri, deel-extensie, Android (4).

## Opzetten

### 1. Supabase
1. Maak een project op supabase.com.
2. **SQL Editor** → plak `supabase/migrations/20261104000000_init.sql` → Run. Dit maakt alle tabellen, de beveiliging (RLS), de fotobucket `media` en de wijk Zuidbroek met de vaste groepen.
3. **Authentication → Providers**
   - *Email*: aan. Zet in **Email Templates → Magic Link** de code erin met `{{ .Token }}` (de app werkt met een 6-cijferige code).
   - *Apple*: aan, met Client ID `app.lrvdlinden.wijkhub`.
4. Jezelf beheerder maken (na je eerste aanmelding in de app):
   ```sql
   update wijk_members set rol = 'beheerder'
   where user_id = (select id from auth.users where email = 'jouw@email.nl');
   ```
5. Nieuwe wijk toevoegen (groepen komen er automatisch bij):
   ```sql
   insert into wijken (slug, naam, plaats, postcodes) values ('wijknaam', 'Wijknaam', 'Plaats', '{1234}');
   ```

### 2. App-sleutels
Vul `WijkHub/Core/SupabaseConfig.swift` in met de project-URL en de **anon key** (Project Settings → API). Zolang die leeg zijn, toont het inlogscherm "De server is nog niet gekoppeld".

### 3. Xcode
```bash
brew install xcodegen   # eenmalig
xcodegen                # maakt WijkHub.xcodeproj
open WijkHub.xcodeproj
```
- Capability **Sign in with Apple** staat al in de entitlements.
- Controleer onder Project → Info → Localizations dat alle 10 talen aan staan.

## Vertalingen
Teksten staan in `tools/translations.py`. Na wijzigen:
```bash
python3 tools/make_strings.py
```
Dit maakt `Localizable.xcstrings` en `InfoPlist.xcstrings` en controleert dat elke tekst uit de code vertaald is.

## Mappen
```
WijkHub/
  App/          app-start, AppModel (sessie, profiel, wijk)
  Core/         Backend (Supabase), modellen, Theme, AppLock, ReviewPrompter
  Components/   BrandMark (logo), Avatar, MoreAppsCard, AppInfoFooter
  Features/     Splash, Auth, Onboarding, Feed, Profile, Settings, Main
  Resources/    Assets, String Catalogs, PrivacyInfo.xcprivacy
supabase/       database-migraties
design/         logo en app-icoon (SVG)
tools/          vertalingen
```

---

Meer apps van de ontwikkelaar: [lrvdlinden.app](https://lrvdlinden.app)
