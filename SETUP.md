# SETUP — co je potřeba naklikat ručně

Návod krok za krokem, co musíte udělat v Firebase Console, Google Cloud Console a Xcode, aby aplikace fungovala. Kód v repozitáři je hotový — tady se jen napojují klíče a účty.

> **Tip:** Dokud nemáte hotové kroky 4–6 (OAuth), můžete aplikaci vyvíjet s mock kalendářem: Nastavení → Vývoj → „Mock kalendář“. Firestore (kroky 1–3) je potřeba vždy.

---

## 1. Firebase projekt a iOS aplikace

1. Jděte na <https://console.firebase.google.com> a klikněte **Add project** (Přidat projekt).
2. Název např. `jahody-objednavky`. Google Analytics můžete **vypnout** (nepotřebujeme).
3. V přehledu projektu klikněte na ikonu **iOS+** (Přidat aplikaci → iOS).
4. **Apple bundle ID:** `cz.jahody.objednavky` — musí přesně odpovídat hodnotě `PRODUCT_BUNDLE_IDENTIFIER` v Xcode (Target Jahody → Signing & Capabilities). Pokud si bundle ID změníte v Xcode, změňte ho stejně i tady.
5. Stáhněte **GoogleService-Info.plist**.
6. Soubor přetáhněte v Xcode do složky **Jahody** (vedle `GoogleService-Info.example.plist`), zaškrtnuté „Copy items if needed“ a cíl **Jahody**.
   - Soubor je v `.gitignore` a **do gitu se necommituje** — v repozitáři je jen `GoogleService-Info.example.plist` jako vzor.
7. Další kroky průvodce („Add Firebase SDK“, „Initialization code“) **přeskočte** — SDK i inicializace už jsou v projektu.

## 2. Přihlašování Googlem (Firebase Auth)

1. Firebase Console → **Build → Authentication → Get started**.
2. Záložka **Sign-in method** → **Google** → **Enable**.
3. Vyplňte „support email“ (váš e-mail) a uložte.

## 3. Firestore databáze a Security Rules

1. Firebase Console → **Build → Firestore Database → Create database**.
2. Region: **eur3 (europe-west)** nebo `europe-west3`. Režim: **production mode**.
3. Záložka **Rules** → vložte obsah souboru [`firestore.rules`](firestore.rules) z tohoto repozitáře → **Publish**.
4. Záložka **Data** → **Start collection** → ID kolekce: `allowedUsers`.
   - Pro každého člena rodiny přidejte dokument, jehož **ID dokumentu je jeho gmailová adresa malými písmeny**, např. `jana.novakova@gmail.com`. Do dokumentu dejte libovolné pole, třeba `name: "Jana"` (dokument nesmí být úplně prázdný).
5. Kolekce `orders` a `products` vytvářet nemusíte — aplikace si je založí sama (produkty se při prvním spuštění naplní výchozím číselníkem).

## 4. Google Calendar API

1. Otevřete <https://console.cloud.google.com> a nahoře vyberte projekt — **stejný projekt, který vytvořil Firebase** (jmenuje se stejně jako Firebase projekt).
2. **APIs & Services → Library** → vyhledejte **Google Calendar API** → **Enable**.

## 5. OAuth consent screen a klient pro iOS

1. Google Cloud Console → **APIs & Services → OAuth consent screen**.
2. Typ uživatelů: pokud používáte běžné gmailové účty, jediná možnost je **External** — zvolte ji a nechte aplikaci v režimu **Testing**.
3. Vyplňte název aplikace (`Jahody`), support e-mail a kontakt vývojáře. Ostatní nechte prázdné → uložit.
4. Sekce **Test users** → **Add users** → přidejte **e-maily všech členů rodiny** (stejné jako v `allowedUsers`). V režimu Testing se přihlásí jen tito uživatelé — nic víc není potřeba, aplikace nejde do ověřování Googlem.
5. (Scopes není nutné vyplňovat — aplikace si o `calendar.events` a `calendar.readonly` řekne při přihlášení a uživatel je odsouhlasí.)
6. **OAuth klient pro iOS už existuje** — vytvořil ho Firebase při přidání iOS aplikace (krok 1). Zkontrolujete ho v **APIs & Services → Credentials** (typ „iOS“).

## 6. URL scheme v Xcode (návrat z přihlášení)

1. Otevřete stažený `GoogleService-Info.plist` a zkopírujte hodnotu klíče **REVERSED_CLIENT_ID** (vypadá jako `com.googleusercontent.apps.1234567890-abc…`).
2. Otevřete soubor `Jahody/Info.plist` a nahraďte placeholder `com.googleusercontent.apps.DOPLNTE-REVERSED-CLIENT-ID` zkopírovanou hodnotou.
   - Alternativně v Xcode: Target **Jahody** → **Info** → **URL Types** → upravte existující schéma.

## 7. Sdílený Google Kalendář

1. Na <https://calendar.google.com> (na počítači) vlevo u „Další kalendáře“ klikněte **+** → **Vytvořit nový kalendář** → název např. **Objednávky farma**.
2. V nastavení tohoto kalendáře → **Sdílet s konkrétními lidmi** → přidejte sourozence s oprávněním **Provádět změny událostí** (nebo vyšším).
3. Každý sourozenec musí pozvánku přijmout, aby kalendář viděl v mobilu (Google Kalendář appka: Nastavení → zapnout synchronizaci tohoto kalendáře).
4. V aplikaci pak: **Nastavení → Cílový kalendář** → vyberte **Objednávky farma**. (Ukládá se `calendarId`, každý člen rodiny si kalendář vybere jednou na svém telefonu.)

## 8. První spuštění

1. Otevřete `Jahody.xcodeproj` v Xcode (16 nebo novější). Xcode si sám stáhne SPM závislosti (firebase-ios-sdk, GoogleSignIn-iOS) — chvíli to trvá.
2. Target **Jahody** → **Signing & Capabilities** → vyberte svůj **Team** (osobní Apple ID stačí; podpis bez placeného účtu vyprší po 7 dnech, pak aplikaci znovu nahrajete).
3. Připojte iPhone, zvolte ho jako cíl a **⌘R**.
4. Přihlaste se Google účtem, který je v `allowedUsers` i v „Test users“.
5. Nastavení → **Cílový kalendář** → vyberte sdílený kalendář.
6. Zadejte zkušební objednávku — do minuty se má objevit v Google Kalendáři všem, s kým je kalendář sdílený.

## 9. Testy

V Xcode **⌘U** — spustí unit testy skládání názvu/popisu události a denních součtů kg.

## 10. Až bude Apple Developer účet (TestFlight)

1. Založte Apple Developer Program (99 $/rok) na stejné Apple ID.
2. V Xcode přepněte Team na nový placený tým (bundle ID `cz.jahody.objednavky` zůstává).
3. App Store Connect → **My Apps → +** → nová aplikace s tímto bundle ID.
4. Xcode → **Product → Archive → Distribute App → TestFlight**.
5. V App Store Connect přidejte sourozence jako **interní testery** (stačí jejich Apple ID e-maily) — dostanou pozvánku do aplikace TestFlight.

---

## Řešení potíží

| Problém | Příčina / řešení |
|---|---|
| Obrazovka „Chybí konfigurace Firebase“ | `GoogleService-Info.plist` není ve složce Jahody nebo není přidaný do targetu. |
| Po přihlášení „Účet nemá přístup“ | E-mail chybí v kolekci `allowedUsers` (ID dokumentu musí být e-mail malými písmeny), nebo nejsou publikovaná pravidla z `firestore.rules`. |
| Google přihlášení spadne zpět do aplikace bez přihlášení | Špatný `REVERSED_CLIENT_ID` v `Jahody/Info.plist` (krok 6). |
| „Access blocked: … has not completed the Google verification process“ | E-mail není v **Test users** na OAuth consent screen (krok 5.4). |
| Objednávky se ukládají, ale události nevznikají | V Nastavení není vybraný cílový kalendář, je zapnutý „Mock kalendář“, nebo není povolené Calendar API (krok 4). |
| Události nevznikají a v detailu je „Nesynchronizováno“ | Zkontrolujte připojení; aplikace to zkouší sama znovu, v detailu objednávky je „Zkusit znovu“. |
