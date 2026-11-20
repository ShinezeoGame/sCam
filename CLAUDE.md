# sCam — notes pour Claude

- **Toujours communiquer avec l'utilisateur en français.** L'interface, les commentaires
  et les messages de commit sont aussi en français.
- Application Flutter pour **Android et Windows** (même code) : un téléphone Android devient
  caméra de surveillance ou babyphone (rôle **Caméra**, Android seulement), regardé depuis
  d'autres appareils sur le Wi-Fi de la maison (rôle **Écran** : le Samsung Galaxy S25 de
  l'utilisateur, la tablette de sDash, le PC Windows). L'utilisateur n'a pas de vieux
  téléphone pour l'instant : n'importe quel Android 7+ peut servir de caméra.
- Architecture :
  - `lib/core/` : `crypto.dart` (appairage X25519 avec engagement, code à 6 chiffres,
    preuves HMAC, `SessionCipher` AES-256-GCM avec compteur par sens), `detection.dart`
    (décision des alertes bruit et mouvement).
  - `lib/data/net/` : `protocol.dart` (ports 47880 et 47881, annonces, `MessageLink` : JSON
    préfixés de leur longueur, chiffrés à partir d'un point précis de l'échange,
    `isLocalAddress`, `isLocalCandidate`), `discovery.dart` (UDP, reprise de sDrop),
    `pairing.dart` (`PairingExchange`, `Handshake`), `mjpeg_server.dart`.
  - `lib/media/` : `media.dart` (interfaces `CameraMedia`, `ScreenMedia`, simulées dans les
    tests), `webrtc_media.dart` (implémentation `flutter_webrtc`).
  - `lib/state/` : `app_controller.dart` (réglages, rôle, messages), `camera_controller.dart`
    (serveur, appairage, écrans connectés, mesures, alertes, MJPEG),
    `screen_controller.dart` (liaisons permanentes aux caméras, alertes, regarder, appairer).
  - `lib/data/system_bridge.dart` ↔ `android/.../MainActivity.kt` (canal `scam/systeme`) :
    autorisations, `ScamService.kt` (service au premier plan), batterie et température,
    `CameraAnalyzer.kt` (niveau sonore, mouvement, JPEG), notifications d'alerte, économie
    de batterie. Sous Windows, `flutter_window.cpp` ne gère que `alerte` (fenêtre qui
    clignote) ; le reste renvoie des valeurs neutres.
- Règles de sécurité à ne pas affaiblir : réseau local uniquement (connexions et candidats
  WebRTC non locaux refusés, aucun serveur STUN/TURN) ; rien n'est transmis à un appareil
  non appairé ; l'appairage n'est accepté que pendant qu'il est ouvert sur la caméra et
  exige la confirmation du code des deux côtés ; tout message après la poignée de main est
  chiffré. Le flux MJPEG est **désactivé par défaut et non chiffré** : c'est dit dans
  l'interface et la documentation, ne pas prétendre le contraire.
- Direction artistique : celle de **sDash**, **sPhone** et **sDrop**. Interface à plat (ni
  texture, ni flou, ni dégradé décoratif), tons chauds, thème clair et sombre, police Outfit.
  - Couleurs uniquement par rôle : `context.colors` / `context.text` (`lib/ui/theme.dart`),
    jamais de couleur en dur dans un widget. Seule exception : `nightFilter` (matrice qui
    éclaircit l'image de nuit), définie dans `theme.dart`.
  - Tuile ambrée = code d'appairage à comparer, alerte récente, écoute en cours ; ses boutons
    utilisent `AppButton(onActive: true)`.
  - Composants dans `lib/ui/widgets/` (`camera_widgets.dart` : vumètre, réglages de caméra,
    code d'appairage) ; chaque page passe par `AppPage` (`page_scaffold.dart`).
  - Zones cliquables d'au moins 44 px. Mise en page étroite, identique sur le téléphone et le
    PC (fenêtre 420 × 760 par défaut, 360 × 480 au minimum) : tout doit tenir sans
    débordement à ces tailles.
- Vérifications avant de pousser : `dart format -l 120 lib test`, `flutter analyze` et
  `flutter test`. `test/core_test.dart` lance une caméra et un écran réels sur des ports
  locaux (`test/support/harness.dart`) ; `test/app_test.dart` parcourt l'interface à trois
  tailles de fenêtre, en clair et en sombre.
- Captures de la documentation : `SCAM_CAPTURES=1 flutter test test/captures_test.dart`.
- Travail sur une branche `claude/…` ; ne pas pousser sur `main` sans que l'utilisateur le
  demande. Chaque envoi sur `main` publie une Release, sauf si seuls des `.md` ou `docs/`
  changent (`paths-ignore` de la CI).
- La CI (`.github/workflows/build.yml`) teste, compile l'APK (`scam-android`) et
  l'application Windows (`scam-windows` : installateur Inno Setup `tools/installer/scam.iss`
  et archive), lance l'exécutable Windows avec `SCAM_ESSAI` (il prépare une offre WebRTC et
  écrit un compte rendu). La Release n'est publiée que sur `main` ou à la demande.
- **Jamais essayé sur un vrai téléphone ni sous Windows au moment de l'écriture** (ni
  téléphone, ni caméra, ni Windows, ni SDK Android dans le conteneur) : toute la partie
  Android (Kotlin, service, analyse, WebRTC réel) n'est vérifiée que par la compilation de
  la CI. Points à surveiller lors des premiers essais : liaison WebRTC interne qui garde le
  micro ouvert, rotation des JPEG, son sur haut-parleur côté écran Android, service au
  premier plan sur Android 14+, économie de batterie Samsung.
- Logo : sCam fait partie de la marque « s » de sPack. Règles : même carré arrondi orange
  `#C2571A`, même trait clair à bouts ronds, le dessin de chaque application est **centré**
  dans le carré, et **le point ambre est posé ensuite dans l'angle en haut à droite**,
  toujours au même endroit et de la même taille (ne jamais décaler le dessin pour lui faire
  de la place). Ici, **une caméra vidéo pour sCam**. Source : `tools/logo/generer_logo.py`,
  **identique dans tous les dépôts de sPack, seule `APPLI_DU_DEPOT` diffère ; le recopier
  dans les autres après chaque modification** → `docs/logo/*.svg`, puis
  `tools/logo/exporter.py` → PNG, icône Windows et icônes Android. Le fond de l'icône
  adaptative Android est la couleur `scam_icon_background` (`values/colors.xml`). Icônes de
  la famille : `docs/logo/famille/`.
- README : section « La famille sPack » = tableau à 4 colonnes repris de sPhone ; sWatt,
  sCam et sBackup y portent « bientôt » tant qu'ils n'ont pas de version publiée (le retirer
  pour sCam à la première Release).
