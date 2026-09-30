# discourse-ballotage-nautas

[ENGLISH](README.md) | [ESPAÑOL](README.es.md) | **DEUTSCH**

> Fork von [DaniW42/discourse-ballotage](https://github.com/DaniW42/discourse-ballotage),
> gepflegt von [Criptonautas](https://github.com/somos-criptonautas). Die vollständige
> Dokumentation (inkl. Unterschiede zum Original) steht auf [Englisch](README.md).

Discourse-Plugin für **geheime Abstimmungen** unter Mitgliedern: **Aufnahmen** mit
schwarzen/weissen Kugeln („Kugelung“) und **Anträge** mit Dafür / Dagegen / Enthaltung.
Gespeichert wird nur, *dass* jemand abgestimmt hat — nie, *wie*.

## Funktionen

- **In Beiträgen:** Kugelungen werden mit `[ballotage id=N]` eingebunden (im Editor über
  ⚙ → „Geheime Kugelung einfügen“); abgestimmt wird direkt im Beitrag. Der Thementitel
  erhält automatisch das Kürzel **[AUFNAHME]** bzw. **[ANTRAG]**, und in Themenlisten
  markiert ein Wahlurnen-Symbol diese Themen.
- **Regeln pro Kugelung:** Aufnahme abgelehnt ab *N* schwarzen Kugeln oder ab *X %* der
  abgegebenen Stimmen; Anträge mit einfacher, Zweidrittel- oder einstimmiger Mehrheit
  (Enthaltungen zählen nur zum Quorum). Optionales Quorum. Regeln sind nach dem Anlegen
  nicht mehr änderbar.
- **Ergebnis:** Beim Ende wird „Angenommen“, „Abgelehnt“ oder „Quorum nicht erreicht“
  samt Beteiligung festgehalten. Pro Kugelung wählbar, wer es sieht: nur die Aufsicht,
  das Ergebnis oder zusätzlich die Stimmenzahlen — nie, wer abgestimmt hat.
- **Benachrichtigungen** beim Start, 24 h vor Ende (an alle, die noch nicht abgestimmt
  haben) und beim Ende. Anlegen, Stornieren, Finalisieren und Löschen erscheinen im
  Staff-Aktionsprotokoll.
- **Seiten:** `/ballotage` listet geplante und laufende Kugelungen (oben rechts:
  „Kugelungen verwalten“ und „Neue Kugelung“ für Berechtigte); `/ballotage/manage` ist die
  Verwaltung für Aufsicht und Admins. Einen Link in der Seitenleiste legst du selbst über
  die normale Seitenleisten-Bearbeitung von Discourse an.

## Geheimhaltung

Keine Datenbank-Verknüpfung zwischen Mitglied und Stimme: die Teilnahme-Tabelle kennt nur,
wer abgestimmt hat (ohne Zeitstempel), die Stimmen sind nur Zähler. Während der Laufzeit
sieht die Aufsicht die Teilnahme, aber keinen Zwischenstand. **Finalisieren** löscht
unwiderruflich die Teilnehmerliste und — sofern nicht bewusst behalten — die
Stimmenzahlen; Titel, Zeitraum, Status und Ergebnis bleiben. Wer direkten
Datenbankzugriff hat, könnte die Zähler live beobachten; das muss organisatorisch
abgesichert werden.

## Einrichtung

Plugin per `git clone` in `plugins/` einbinden und `./launcher rebuild app` ausführen
(siehe [englische Anleitung](README.md#installation)). Danach `ballotage_enabled`
aktivieren, Abstimmungsgruppe (`ballotage_voting_group`) und Aufsichtsgruppe
(`ballotage_oversight_group`) wählen, optional eine feste Zeitzone
(`ballotage_timezone`, leer = automatisch) und die Verwaltung durch die Aufsicht
(`ballotage_oversight_can_manage`).

Voraussetzung: Discourse 2026.7 oder neuer. Code: GPL-3.0 ([LICENSE](LICENSE)).
Dieser Text: [CC BY-NC-SA 4.0](CC-BY-NC-SA-4.0.txt).
