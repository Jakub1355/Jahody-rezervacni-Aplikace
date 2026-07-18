# 🍓 Jahody — objednávky z farmy

Interní iOS aplikace pro rodinu (3–5 lidí): bleskové zadání objednávky během telefonátu, denní přehled kolik kg jahod nachystat, a automatické propsání každé objednávky jako události do sdíleného Google Kalendáře.

Zadání a kontext: [ZADANI-rezervacni-aplikace.md](ZADANI-rezervacni-aplikace.md) · Ruční nastavení (Firebase, OAuth, kalendář): **[SETUP.md](SETUP.md)**

## Co aplikace umí (MVP)

- **Nová objednávka do 15 vteřin** — našeptávání jmen z historie (doplní i telefon), chipy 1/2/3/5 kg + vlastní množství s desetinnou čárkou, dny Dnes/Zítra/Pozítří, časy po 30 minutách, další produkty jedním klepnutím.
- **Diktování hlasem** — místo psaní lze celou objednávku nadiktovat („Jana Nováková, telefon 777 123 456, přijede zítra v pět, chce tři kila jahod“); aplikace rozpozná jméno, telefon, den, čas i množství a předvyplní formulář. Rozpoznávání běží i offline. Vše jde následně ručně upravit.
- **Přehled po dnech** — sekce Dnes/Zítra/další dny se **součtem kg jahod v hlavičce dne** (+ součty dalších položek), historie starších objednávek.
- **Google Kalendář** — každá objednávka se asynchronně propíše jako událost (`Jana Nováková – 3 kg jahod +vejce`) do zvoleného sdíleného kalendáře; úprava událost aktualizuje, zrušení ji smaže. Selhání nikdy neblokuje uložení — automatický retry + indikátor „nesynchronizováno“.
- **Offline** — Firestore s persistentní cache: objednávka zadaná bez signálu se po připojení sama synchronizuje (data i kalendář).
- **Jen pro rodinu** — Google Sign-In přes Firebase Auth + Firestore Security Rules s kolekcí `allowedUsers`.
- Celá aplikace česky, velké dotykové plochy, světlý i tmavý režim.

## Technický stack

SwiftUI (iOS 17+) · Firebase Auth + Firestore (offline persistence) · Google Sign-In · Google Calendar API (REST, bez vlastního backendu)

## Struktura projektu

```
Jahody/
├── JahodyApp.swift          – vstupní bod, Firebase, deep-linky Google Sign-In
├── Models/                  – Order, OrderItem, Product (sdílený kontrakt s budoucím webem)
├── Services/
│   ├── AppModel.swift       – kompozice služeb
│   ├── AuthService.swift    – Firebase Auth + Google Sign-In (Calendar scopes)
│   ├── OrderStore.swift     – Firestore orders, našeptávání, offline zápisy
│   ├── ProductStore.swift   – číselník products + výchozí naplnění
│   ├── CalendarService.swift        – protokol + Google Calendar API + mock
│   └── CalendarSyncManager.swift    – asynchronní synchronizace s retry
│   └── SpeechDictationService.swift – rozpoznávání české řeči pro diktování
├── Utilities/               – české formáty, skládání událostí, denní součty, parser diktování
└── Views/                   – Nová objednávka / Přehled / Detail / Nastavení
JahodyTests/                 – unit testy (název/popis události, součty kg, formáty)
firestore.rules              – Security Rules s allowedUsers
```

Datový model ve Firestore (`orders`, `products`, `allowedUsers`) je **sdílený kontrakt** — veškerá pravidla drží data, ne UI, aby později šla postavit jednoduchá webová verze pro stará zařízení (poslední fáze zadání).

## Kde mít projekt: GitHub vs. lokální Mac

**Samotný GitHub repozitář nestačí — pro vývoj a build v Xcode potřebujete projekt i lokálně na Macu.** Xcode staví z lokálních souborů, na iPhone podepisuje a nahrává z lokální kopie a `GoogleService-Info.plist` (který v gitu není) leží jen u vás na disku. GitHub slouží jako záloha, historie a místo, kam Claude Code posílá změny.

Postup:

```bash
# jednorázově naklonovat do vaší složky na Macu
cd "/Users/jakub_valek/Library/Mobile Documents/com~apple~CloudDocs/Developer/Claude Code"
git clone <URL-repozitáře> "Jahody rezervacni Aplikace"
cd "Jahody rezervacni Aplikace"
open Jahody.xcodeproj
```

Když někde (třeba tady přes Claude Code na webu) přibudou změny, stáhnete je do místní kopie přes `git pull`. Naopak změny z Macu nahrajete přes `git commit` + `git push`.

> Poznámka: složka je na iCloud Drive (`com~apple~CloudDocs`). To funguje, jen se vyhněte tomu mít stejný projekt otevřený a měněný na dvou zařízeních zaráz kvůli konfliktům iCloudu. Git je tu spolehlivější „záloha“ než samotný iCloud.

## Vývoj bez klíčů

`CalendarService` je protokol s mock implementací — v Nastavení → Vývoj lze zapnout **Mock kalendář** a vyvíjet/testovat celý tok objednávek dřív, než je hotový OAuth. Bez `GoogleService-Info.plist` aplikace zobrazí návodnou obrazovku.

## Fáze 2 (v architektuře připraveno, neimplementováno)

Stavy objednávek (nachystaná/vyzvednutá — `OrderStatus` je rozšiřitelný string enum), veřejný objednávkový formulář, načítání z WhatsApp/Messengeru, ceny a platby, push notifikace, webová verze, Android.
