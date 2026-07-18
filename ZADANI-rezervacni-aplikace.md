# Zadání pro Claude Code — Rezervační aplikace pro objednávky z farmy („Jahody")

> **Jak použít:** Naklonuj si nový (prázdný) repozitář na Mac, v jeho složce spusť `claude` a vlož celý tento text jako první prompt. Claude Code podle něj založí a naprogramuje celý projekt. Stejně to funguje i v nové session Claude Code na webu připojené k novému repozitáři.

---

## Kontext

Jsme rodinná farma. Prodáváme jahody, mléčné výrobky, sýry, vajíčka, sirupy a marmelády. V jahodové sezóně chodí velké množství objednávek — lidé volají, píšou SMS, WhatsApp nebo Messenger několika různým sourozencům a evidence se dnes vede ručně ve WhatsAppu. Je v tom chaos: neví se, kdo co objednal, na kdy, a kolik jahod je potřeba na který den nachystat.

Chceme jednoduchou **interní aplikaci pro rodinu** (cca 3–5 lidí). Když někdo zavolá, kdokoliv z nás objednávku během hovoru zadá do aplikace a ta ji automaticky propíše jako událost do **sdíleného Google Kalendáře**, který máme všichni v mobilu.

Aplikace **není určena zákazníkům** — objednávky zadává pouze rodina.

## Cíl první verze (MVP)

Nativní iOS aplikace, která:

1. umožní **bleskově zadat objednávku během telefonátu** — cíl do 15 vteřin,
2. dá **denní přehled**, co je potřeba nachystat (hlavně celkový počet kg jahod na den),
3. každou objednávku **automaticky vytvoří jako událost ve sdíleném Google Kalendáři** (a při úpravě/zrušení ji aktualizuje/smaže).

## Technický stack

- **SwiftUI, iOS 17+**, vývoj v Xcode na Macu (Mac i Xcode mám; placený Apple Developer účet zatím nemám — viz Distribuce).
- **Sdílená data: Firebase Firestore** (free tier) se zapnutou **offline persistencí** — na farmě není vždy signál; zápis musí projít offline a synchronizovat se později.
- **Přihlášení: Google Sign-In přes Firebase Auth** — stejný Google účet se použije i pro přístup ke Kalendáři.
- **Google Calendar API** (scope `https://www.googleapis.com/auth/calendar.events` + čtení seznamu kalendářů) pro vytváření, úpravu a mazání událostí ve zvoleném sdíleném kalendáři.
- **Žádný vlastní backend** — aplikace komunikuje přímo s Firestore a Calendar API.
- Přístup do aplikace omez na povolené účty: v Firestore veď kolekci `allowedUsers` (e-maily rodiny) a přes Firestore Security Rules pusť ke čtení/zápisu jen je.

## Datový model (Firestore)

**orders**
- `id`
- `customerName` (povinné)
- `phone` (nepovinné)
- `items`: pole položek `{ productName, quantity, unit }` — jahody jsou jen jedna z položek, typicky první
- `pickupAt` (datum + čas, kdy si zákazník **přijede vyzvednout** — ne kdy se má sbírat)
- `note` (volný text)
- `status`: `aktivni` / `zrusena` — rozpracované stavy („nachystaná", „vyzvednutá") přijdou až ve fázi 2, s polem proto počítej tak, aby šly hodnoty snadno přidat
- `createdBy` (e-mail/jméno člena rodiny)
- `calendarEventId` (ID události v Google Kalendáři, kvůli pozdější úpravě/smazání)
- `createdAt`, `updatedAt`

**products** (číselník, editovatelný v Nastavení)
- `name`, `unit` (`kg` / `ks` / `l`), `isActive`, `sortOrder`
- Výchozí naplnění: Jahody (kg), Vajíčka (ks), Sirup (ks), Marmeláda (ks), Sýr (ks), Mléko (l), Tvaroh (ks)

**Našeptávání zákazníků:** jména a telefony našeptávej z historie objednávek (odvozeno z `orders`, samostatná kolekce není nutná).

## Obrazovky

### 1. Nová objednávka (hlavní obrazovka, optimalizovaná na rychlost)
- Jméno — textové pole s našeptáváním z historie (vybráním se doplní i telefon).
- Telefon — nepovinný.
- Jahody — rychlé chipy **1 / 2 / 3 / 5 kg** + vlastní hodnota (podpora desetinných čísel, např. 0,5 kg; česká klávesnice s čárkou).
- Den vyzvednutí — chipy **Dnes / Zítra / Pozítří** + výběr jiného data.
- Čas vyzvednutí — rychlý výběr po 30 minutách.
- Další položky — jedním klepnutím přidat produkt z číselníku, u něj množství.
- Poznámka — volný text.
- **Uložit** — okamžitě zapíše do Firestore; vytvoření události v kalendáři proběhne asynchronně a **nesmí blokovat uložení** (při selhání automatický retry, u objednávky indikátor „nesynchronizováno s kalendářem").

### 2. Přehled objednávek
- Sekce **Dnes / Zítra / Další dny** (a možnost podívat se do historie).
- V hlavičce každého dne **součet objednaných kg jahod** (případně i počty dalších položek) — smyslem je vidět, **kolik je na který den objednáno**, podle toho se plánuje sběr.
- Řádek objednávky: čas, jméno, položky zkráceně.
- Žádné odškrtávání stavů (nachystáno/vyzvednuto) — to případně až ve fázi 2.

### 3. Detail objednávky
- Úprava všech polí (propíše se do kalendářní události přes `calendarEventId`).
- Tlačítko **Zavolat** / **SMS** na uložený telefon.
- **Zrušit objednávku** — nastaví status `zrusena` a smaže událost z kalendáře.

### 4. Nastavení
- Přihlášený Google účet (přihlásit/odhlásit).
- **Výběr cílového kalendáře** ze seznamu kalendářů účtu (ukládat `calendarId`, ne natvrdo „primary" — používáme zvláštní sdílený kalendář jen pro objednávky).
- Správa číselníku produktů (přidat, přejmenovat, skrýt).

## Chování Google Kalendáře

- Název události: `Jana Nováková – 3 kg jahod`; pokud má objednávka další položky, přidej ` +vejce, sirup` (jen názvy).
- Začátek = `pickupAt`, délka 15 minut.
- Popis události: kompletní položky, poznámka, telefon, kdo objednávku zadal.
- Úprava objednávky událost aktualizuje, zrušení ji smaže.
- Notifikace neřeš v aplikaci — sdílený kalendář mají všichni v mobilu, upozornění zajistí Google/Apple Kalendář.

## UI a jazyk

- Celá aplikace **česky** (texty, formáty data „čtvrtek 23. 7.", desetinná čárka).
- Velké dotykové plochy — často se zadává jednou rukou s telefonem u ucha.
- Světlý i tmavý režim.

## Co v MVP NEDĚLAT (jen nechat v architektuře prostor)

**Fáze 2:**
- Stavy objednávek (nachystaná / vyzvednutá) a jejich odškrtávání v přehledu.
- Veřejný objednávkový formulář pro zákazníky.
- Automatické načítání objednávek z WhatsApp/Messenger (Meta Business API).
- Ceny, platby, účtenky.
- Vlastní push notifikace.

**Poslední fáze:**
- **Jednoduchá webová verze** pro stará zařízení, na která už nativní aplikace nejde nainstalovat (např. iPad Mini 4 se starým iOS). Proto žádnou logiku neschovávej jen do aplikace — veškerá data a pravidla drž ve Firestore tak, aby stejná data mohl později obsluhovat i webový klient; struktura dat v tomto zadání je sdílený kontrakt.
- Android verze.

## Postup implementace

1. Založ Xcode projekt (SwiftUI, iOS 17+), Swift Package Manager závislosti: `firebase-ios-sdk` (Auth, Firestore), `GoogleSignIn-iOS`.
2. Navrhni vrstvy: `Models`, `Services` (`OrderStore`, `CalendarService` jako protokol s reálnou implementací přes Calendar API **a mock implementací**, aby šla appka vyvíjet a testovat dřív, než budou hotové klíče), `Views`.
3. Nejdřív zprovozni tok **zadání objednávky → Firestore → přehled dnů** (s mock kalendářem), pak přihlášení Googlem, pak reálnou synchronizaci kalendáře.
4. Vytvoř **SETUP.md** s přesným návodem naklikání, co musím udělat ručně:
   - založení Firebase projektu, přidání iOS aplikace, stažení `GoogleService-Info.plist` (do gitu nekomitovat — přidej do `.gitignore` a nech v repu `GoogleService-Info.example.plist`),
   - zapnutí Google Calendar API v Google Cloud Console, OAuth consent screen (typ Internal/testovací uživatelé = e-maily rodiny), OAuth client pro iOS, URL schemes v Xcode,
   - nastavení Firestore Security Rules s `allowedUsers`,
   - vytvoření sdíleného Google Kalendáře a nasdílení sourozencům.
5. Unit testy na klíčovou logiku: skládání názvu/popisu události, denní součty objednaných kg.

## Akceptační kritéria

- [ ] Zadání běžné objednávky (jméno z historie, 2 kg jahod, zítra 17:00) zvládnu do 15 vteřin.
- [ ] Objednávka se do ~1 minuty objeví jako událost ve sdíleném Google Kalendáři se správným názvem, časem a popisem.
- [ ] Úprava času objednávky posune událost v kalendáři; zrušení objednávky událost smaže.
- [ ] Přehled ukazuje správný součet kg jahod pro každý den.
- [ ] Objednávka zadaná bez signálu se po obnovení připojení sama synchronizuje (Firestore i kalendář).
- [ ] Druhý člen rodiny na svém iPhonu vidí novou objednávku bez zásahu (živě přes Firestore).
- [ ] Nepřihlášený / nepovolený Google účet se k datům nedostane.

## Distribuce (poznámka, nic k implementaci)

- Plán: **nejdřív aplikace, potom si založím Apple Developer Program (99 $/rok)** a rozdám ji sourozencům přes **TestFlight**. V projektu s tím rovnou počítej — čisté bundle ID, verzování, název a ikona aplikace — ať pak nahrání do TestFlightu nic nebrzdí.
- Než účet bude, testuji přes Xcode na vlastním iPhonu (podpis bez placeného účtu vyprší po 7 dnech, pak stačí aplikaci znovu nahrát).
