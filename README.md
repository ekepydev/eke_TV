# STB Player 1.1 (Flutter)

IPTV plejer za tvoje vlastite pretplate. Radi bez servera i bez proxyja: Android, Android TV (Axen i sl.),
Chromebook (Android aplikacija) i Windows. Aplikacija ne sadrži nikakav sadržaj.

## Šta može

**Liste (više njih, biraš u zaglavlju):**
- M3U link (ako je to zapravo Xtream `get.php?username=..&password=..`, aplikacija to prepozna i uključi filmove, serije i EPG)
- M3U fajl s uređaja (kopira se u aplikaciju)
- Xtream Codes (server, korisnik, lozinka)
- Portal + MAC (Stalker/MAG emulacija)

**TV uživo:** kategorije, pretraga, favoriti, nedavno, program (EPG: sada/slijedi + cijeli raspored),
zapping, direktan unos broja kanala (0–9), zadnji kanal, automatski ponovni pokušaj kod prekida.

**Filmovi i serije** (Xtream pretplate): glavna kategorija je **Novo**, ostale kategorije biraš u zaglavlju;
postere, opis, ocjenu, sezone i epizode; nastavak gledanja od mjesta gdje si stao; automatski prelazak na sljedeću epizodu.

**Plejer:** titlovi i audio zapisi, online titlovi (OpenSubtitles: bosanski, hrvatski, srpski; zadani jezik se bira u Postavkama),
omjer slike, brzina, tajmer za isključivanje, ekran ne gasi dok gledaš, cijeli ekran (F), jačina, mute.

**Postavke:** tamni/svijetli/sistemski izgled, jezik titla, OpenSubtitles ključ, zadani EPG, skok naprijed/nazad,
**sve prečice se mogu podesiti** (zadano: F cijeli ekran, ↑/↓ jačina, →/← naprijed/nazad ili sljedeći/prethodni kanal,
M mute, L zadnji kanal, S titlovi, Z omjer slike, I info, Razmaknica pauza, Esc nazad).

## Kako dobiti aplikaciju (GitHub, besplatno)

1. Uploaduj sadržaj ovog foldera u svoj repozitorij (zamijeni stare fajlove; mora ići i skriveni `.github`).
2. **Actions → build → Run workflow.** Nakon 10–15 min fajlovi su u **Artifacts** (`android`, `windows`).
3. Za Axen TV probaj `stb-player-android-armv7.apk`, a za telefon/noviji TV/Chromebook `...arm64.apk`.
   Windows: raspakuj ZIP i pokreni `stb_player.exe`.

Ako Actions pokaže grešku, pošalji tekst greške. Korak "Analiza koda" je informativan i ispisuje probleme u kodu.

## Titlovi (OpenSubtitles)

1. Napravi besplatan račun na opensubtitles.com, pa u profilu **API consumers → New consumer** i kopiraj ključ.
2. Zalijepi ga u **Postavke → Titlovi**. (Korisničko ime i lozinka su opcionalni, a povećavaju dnevni limit preuzimanja.)
3. U plejeru: ikona titlova → *Traži titlove*, ili automatski ako je uključeno "Automatski uključi titl".

## Ograničenja

- Filmovi i serije rade samo kod Xtream pretplata (M3U/Stalker ih nemaju).
- EPG za M3U radi ako lista ima `tvg-id` i XMLTV link (iz zaglavlja liste ili iz Postavki). Veliki XMLTV fajlovi (>50 MB) mogu biti spori na slabim TV-ima.
- Nije uključeno: snimanje, catch-up/timeshift, Chromecast, roditeljska zaštita (vidi prijedloge).
- Kod nije probano na svim uređajima; prijavi greške s tačnim tekstom.
