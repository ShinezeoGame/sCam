<p align="center"><img src="docs/logo/scam-logo-1024.png" width="148" alt="Logo sCam : une caméra vidéo et un point ambre, sur fond orange"></p>

<h1 align="center">sCam</h1>

<p align="center"><b>Un téléphone Android (ou un PC) devient caméra de surveillance ou babyphone, chez vous, sur votre Wi-Fi.</b></p>

<p align="center">
  <a href="https://github.com/ShinezeoGame/sCam/releases/latest/download/scam.apk"><img alt="Télécharger pour Android (APK)" src="https://img.shields.io/badge/T%C3%A9l%C3%A9charger-pour%20Android-F0A257?style=for-the-badge&logo=android&logoColor=white&labelColor=3B2516"></a>
  <a href="https://github.com/ShinezeoGame/sCam/releases/latest/download/scam-setup.exe"><img alt="Télécharger pour Windows (installateur)" src="https://img.shields.io/badge/T%C3%A9l%C3%A9charger-pour%20Windows-F0A257?style=for-the-badge&logo=windows&logoColor=white&labelColor=3B2516"></a>
  <a href="https://github.com/ShinezeoGame/sCam/releases/latest"><img alt="Version" src="https://img.shields.io/github/v/release/ShinezeoGame/sCam?style=for-the-badge&label=version&color=C2692B&labelColor=3B2516"></a>
</p>

Le téléphone que vous n'utilisez plus dort dans un tiroir ? Posez-le dans la chambre du
bébé ou face à la porte d'entrée, branchez-le, et regardez la pièce depuis votre téléphone
ou votre PC : l'image et le son en direct, et une alerte quand bébé pleure ou que quelque
chose bouge. Pas de compte, pas d'abonnement, et rien ne sort de la maison.

<p align="center">
  <img src="docs/captures/ecran.png" width="270" alt="Écran : deux caméras, une alerte de bruit à l'instant">
  <img src="docs/captures/direct.png" width="270" alt="Thème sombre : image en direct, son, éclaircir, lampe">
  <img src="docs/captures/camera.png" width="270" alt="Le téléphone caméra : aperçu, état et appairage ouvert">
</p>

## Pourquoi sCam

- **Une seconde vie pour un vieux téléphone.** Il a déjà une caméra, un micro, une lampe, du
  Wi-Fi et une batterie de secours : c'est un babyphone tout trouvé.
- **Chez vous, et seulement chez vous.** sCam ne fonctionne que sur le réseau de la maison :
  aucun serveur, aucun nuage, l'image ne passe jamais par Internet.
- **Seuls vos appareils regardent.** Chaque écran est appairé à la caméra avec un code à
  vérifier des deux côtés, et tout ce qui circule est chiffré.

## Ce que fait sCam

### 🎥 L'image et le son en direct
Touchez une caméra : l'image et le son arrivent avec très peu de retard (WebRTC, de
l'appareil à l'appareil). Coupez le son d'un geste, passez en plein écran.

### 👶 Babyphone
Activez « Écouter en arrière-plan » : sur Android, le son continue quand vous quittez sCam
ou que l'écran s'éteint, comme un babyphone.

### 🔔 Alerte bruit et alerte mouvement
La caméra écoute et regarde en continu. Un bruit qui dure (des pleurs, une voix), ou un
mouvement dans l'image, et tous vos écrans reçoivent une alerte, même quand sCam est en
arrière-plan sur le téléphone. Le seuil du bruit et la sensibilité au mouvement se règlent
avec un niveau en direct sous les yeux ; une porte qui claque seule ne déclenche rien.

### 🎞️ Extraits vidéo à chaque alerte
Quand une alerte se déclenche, la caméra Android enregistre les 30 secondes qui suivent,
image et son. Depuis votre écran, vous voyez la liste des extraits, vous les téléchargez
(dans la galerie du téléphone, ou le dossier Vidéos du PC), vous les regardez et vous les
effacez. Ils restent chez vous : sur la caméra, puis sur l'écran qui les télécharge.

### 🔦 Lampe, objectif et nuit
Allumez la lampe du téléphone caméra à distance, passez de l'objectif arrière à l'objectif
avant, et éclaircissez l'image sur votre écran quand la pièce est sombre.

### 🔋 La caméra veille, écran éteint
Le téléphone caméra continue écran éteint, et vous voyez à distance sa batterie et sa
température (et s'il chauffe).

### 🏠 Plusieurs caméras nommées
« Chambre de Léo », « Entrée » : appairez autant de caméras que vous voulez, et regardez-les
depuis votre téléphone, une tablette ou le PC Windows.

### 💻 Le PC peut aussi filmer
Pas de téléphone libre ? La webcam et le micro d'un PC Windows font une caméra sCam, avec les
mêmes alertes. Le PC ne se met pas en veille tant qu'il filme.

### 📺 Prêt pour sDash et Home Assistant
Sur demande, la caméra peut aussi offrir un flux MJPEG local, protégé par mot de passe, que
sDash ou Home Assistant savent afficher. Il est désactivé par défaut (voir la
[foire aux questions](#questions-fréquentes)).

### 🌗 Clair ou sombre
Comme toute la famille sPack, sCam suit le thème de l'appareil, ou celui que vous choisissez.

## Prise en main

1. **Installez sCam** sur l'appareil qui servira de caméra (téléphone Android 7 ou plus
   récent, ou PC Windows avec webcam) et sur celui qui regardera (téléphone Android ou PC
   Windows), connectés au même Wi-Fi.
2. **Choisissez un rôle** : « Caméra » sur l'appareil posé dans la pièce (donnez-lui un
   nom), « Écran » sur l'autre.
3. **Appairez-les** : sur la caméra, touchez « Appairer un écran » ; sur l'écran, « Ajouter
   une caméra ». Vérifiez que le même code à six chiffres s'affiche des deux côtés, et
   confirmez. C'est tout.

Le guide complet est dans [docs/GUIDE.md](docs/GUIDE.md).

## Questions fréquentes

**Est-ce que je peux regarder depuis l'extérieur de la maison ?**
Non, et c'est voulu : sCam ne fonctionne que sur le réseau local, rien ne passe par Internet.

**Qui peut voir l'image ?**
Seuls les écrans appairés, après vérification du code sur les deux appareils. L'image et le
son sont chiffrés. Un appareil non appairé est refusé avant d'avoir rien vu.

**Le téléphone caméra doit-il rester allumé ?**
L'écran peut s'éteindre, mais sCam doit rester ouvert (ne le fermez pas depuis les applis
récentes). Laissez le téléphone branché, et autorisez sCam à ignorer l'économie de batterie
(bouton dans les réglages ; chez Samsung, « Batterie → Non restreinte »).

**Le PC peut-il servir de caméra ?**
Oui, avec sa webcam et son micro. Il n'a ni lampe, ni objectif avant et arrière, et il
n'enregistre pas d'extraits (c'est réservé aux caméras Android). Laissez sCam ouvert : la
fenêtre peut être réduite.

**Et le flux MJPEG pour sDash ou Home Assistant ?**
Activez-le dans les réglages de la caméra : sCam affiche l'adresse, l'utilisateur et le mot
de passe à recopier. Attention : ce flux-là n'est **pas chiffré** (seulement protégé par mot
de passe), et il ne transporte que l'image. C'est pourquoi il est désactivé par défaut.

**sCam enregistre-t-il des vidéos ?**
Seulement à chaque alerte, et si l'option est activée sur la caméra : les 30 secondes qui
suivent l'alerte, gardées sur la caméra (les 30 derniers extraits). Le direct, lui, n'est
jamais enregistré. Les secondes *avant* l'alerte ne sont pas dans l'extrait.

## La famille sPack

sCam fait partie de **sPack**, une famille d'applications pratiques pour la maison, toutes
dans le même style.

| | | | |
| :---: | :---: | :---: | :---: |
| <a href="https://github.com/ShinezeoGame/sDash"><img src="docs/logo/famille/sdash.png" width="72" alt="Logo sDash"></a> | <a href="https://github.com/ShinezeoGame/sPhone"><img src="docs/logo/famille/sphone.png" width="72" alt="Logo sPhone"></a> | <a href="https://github.com/ShinezeoGame/sDrop"><img src="docs/logo/famille/sdrop.png" width="72" alt="Logo sDrop"></a> | <a href="https://github.com/ShinezeoGame/sPing"><img src="docs/logo/famille/sping.png" width="72" alt="Logo sPing"></a> |
| **[sDash](https://github.com/ShinezeoGame/sDash)**<br>Toute la maison sur une tablette | **[sPhone](https://github.com/ShinezeoGame/sPhone)**<br>L'écran du téléphone sur le PC | **[sDrop](https://github.com/ShinezeoGame/sDrop)**<br>Fichiers et textes entre téléphone et PC | **[sPing](https://github.com/ShinezeoGame/sPing)**<br>Les notifications du téléphone sur le PC |
| <a href="https://github.com/ShinezeoGame/sWatt"><img src="docs/logo/famille/swatt.png" width="72" alt="Logo sWatt"></a> | <img src="docs/logo/famille/scam.png" width="72" alt="Logo sCam"> | <a href="https://github.com/ShinezeoGame/sBackup"><img src="docs/logo/famille/sbackup.png" width="72" alt="Logo sBackup"></a> |   |
| **[sWatt](https://github.com/ShinezeoGame/sWatt)**<br>La consommation électrique de la maison<br><sub>bientôt</sub> | **sCam**<br>Un vieux téléphone en caméra ou babyphone<br><sub>bientôt</sub> | **[sBackup](https://github.com/ShinezeoGame/sBackup)**<br>Les photos du téléphone sauvegardées sur le NAS<br><sub>bientôt</sub> |   |

---

<sub>Fonctionnement, développement et logo : voir [docs/DEVELOPPEMENT.md](docs/DEVELOPPEMENT.md).
Police [Outfit](https://github.com/Outfitio/Outfit-Fonts) sous licence SIL Open Font License 1.1.</sub>
