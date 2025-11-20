# QA Checklista – Del C

| # | Flöde | Automatisering | Status | Notering |
|---|-------|----------------|--------|----------|
| 1 | Skapa kvitto → koppla till budget → exportera CSV | Manuell | ✅ Pass | Bekräftat att exportresurs respekterar behörigheter och att fil levereras. |
| 2 | Skanna kvitto via OCR → spara → trigga påminnelser | Manuell | ✅ Pass | Deadlines schemaläggs och visas i dev-status. |
| 3 | Skapa presentkort med PIN → kör export → radera | Manuell | ✅ Pass | PIN återkrypteras och export respekterar export-tillstånd. |
| 4 | Lägg till budgetkategori → logga utgift → kontrollera diagram | Manuell | ✅ Pass | BudgetChart uppdateras utan stutter och visar rätt förbrukning. |
| 5 | Importera (placeholder) budget CSV | Manuell | ⚠️ Pending | UI svarar med "Kommer snart" och behåller interaktion. |
| 6 | Autogiro med trial → synka påminnelser → kontrollera i dev-status | Manuell | ✅ Pass | Trial- och binding-påminnelser visas och kan avaktiveras. |
| 7 | Skapa kostnadsdelning → generera avräkning → aktivera påminnelse | Manuell | ✅ Pass | Påminnelse går att toggla och syns i notislistan. |
| 8 | Delning: bjud in användare med export | Manuell | ✅ Pass | ShareStatusChip uppdateras och exportknappar följer behörighet. |
| 9 | Språkbyte till engelska → verifiera sök och tomt-stater | Manuell | ✅ Pass | Alla nya strängar är översatta och visas korrekt. |
|10 | Provocera fel (kastad exception i dialog) → observera error boundary | Manuell | ✅ Pass | Global felbanner visas med logg och kan avfärdas. |

> Not: Flöde 5 väntar på färdig importfunktionalitet men UI-upplevelsen är kontrollerad.