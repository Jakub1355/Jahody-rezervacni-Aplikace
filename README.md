# 🍓 Jahody — objednávky z farmy

Interní iOS aplikace pro rodinu (3–5 lidí): bleskové zadání objednávky během telefonátu, denní přehled kolik kg jahod nachystat, a automatické propsání každé objednávky jako události do sdíleného Google Kalendáře.

Zadání a kontext: [ZADANI-rezervacni-aplikace.md](ZADANI-rezervacni-aplikace.md) · Ruční nastavení (Firebase, OAuth, kalendář): **[SETUP.md](SETUP.md)**

## Co aplikace umí (MVP)

- **Nová objednávka do 15 vteřin** — našeptávání jmen z historie (doplní i telefon), chipy 1/2/3/5 kg + vlastní množství s desetinnou čárkou, dny Dnes/Zítra/Pozítří, časy po 30 minutách, další produkty jedním klepnutím.
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
├── Utilities/               – české formáty, skládání událostí, denní součty
└── Views/                   – Nová objednávka / Přehled / Detail / Nastavení
JahodyTests/                 – unit testy (název/popis události, součty kg, formáty)
firestore.rules              – Security Rules s allowedUsers
```

Datový model ve Firestore (`orders`, `products`, `allowedUsers`) je **sdílený kontrakt** — veškerá pravidla drží data, ne UI, aby později šla postavit jednoduchá webová verze pro stará zařízení (poslední fáze zadání).

## Vývoj bez klíčů

`CalendarService` je protokol s mock implementací — v Nastavení → Vývoj lze zapnout **Mock kalendář** a vyvíjet/testovat celý tok objednávek dřív, než je hotový OAuth. Bez `GoogleService-Info.plist` aplikace zobrazí návodnou obrazovku.

## Fáze 2 (v architektuře připraveno, neimplementováno)

Stavy objednávek (nachystaná/vyzvednutá — `OrderStatus` je rozšiřitelný string enum), veřejný objednávkový formulář, načítání z WhatsApp/Messengeru, ceny a platby, push notifikace, webová verze, Android.
