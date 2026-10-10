# STB Player (Flutter) – Android, Android TV, Chromebook, Windows

IPTV aplikacija bez servera: radi direktno s provajderom. Liste (M3U link, Xtream, Portal + MAC)
i favoriti se čuvaju lokalno na uređaju. Možeš imati više lista i birati među njima.

## Kako dobiti aplikaciju (besplatno, preko GitHuba)

1. Napravi besplatan račun na https://github.com i novi repozitorij (npr. `stb-player`).
2. Uploaduj sadržaj ovog foldera u repozitorij (cijeli folder, uključujući skriveni `.github`).
3. Idi na **Actions → build → Run workflow** (ili napravi tag, npr. `v1.0.0`).
   Za tag: u repozitoriju **Releases → Create new release → tag `v1.0.0`**.
4. Nakon ~10–15 min fajlovi su u **Actions → build → Artifacts** (ili u **Releases** ako si koristio tag).

## Koji fajl koji uređaj

| Uređaj | Fajl |
|---|---|
| Starija Android TV (Axen i sl., najčešće 32-bit) | `stb-player-android-armv7.apk` |
| Noviji telefon / Android TV / Chromebook | `stb-player-android-arm64.apk` |
| Chromebook s Intel/AMD procesorom | `stb-player-android-x86_64.apk` |
| Windows 10/11 | `stb-player-windows.zip` – raspakuj cijeli folder, pokreni `stb_player.exe` |

Ako ne znaš koji APK, probaj `armv7` (radi na većini uređaja, samo malo sporije).

## Instalacija

- **Android telefon:** otvori APK, dozvoli "instalaciju iz nepoznatih izvora".
- **Android TV:** prebaci APK na USB ili instaliraj aplikaciju *Downloader* i upiši link do APK-a (iz GitHub Releases), pa instaliraj.
- **Chromebook:** uključi Android aplikacije (Postavke → Aplikacije → Google Play), a APK instaliraj
  preko Files aplikacije (dvoklik na APK) ili uz ADB.

## Upravljanje

- **Daljinski (TV):** gore/dolje ili CH+/CH- mijenjaju kanal, OK pokazuje/skriva info, Play/Pause, Back vraća na listu.
- **Telefon:** dodir prikazuje kontrole, prevlačenje gore/dolje mijenja kanal.
- **Windows:** strelice gore/dolje, razmaknica = pauza, Esc = nazad.

## Ograničenja prve verzije

Samo live TV (nema VOD/serija/EPG), nema fullscreen dugmeta na Windowsu, nema uvoza M3U fajla (samo link),
iOS/macOS/Linux/Samsung/LG nisu još uključeni.
