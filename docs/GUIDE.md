[← Retour à la présentation](../README.md)

# Guide de sCam

## Installation

- **Téléphone ou tablette Android** (caméra ou écran) : téléchargez
  [`scam.apk`](https://github.com/ShinezeoGame/sCam/releases/latest/download/scam.apk), ouvrez-le
  et autorisez l'installation d'applications de sources inconnues si Android le demande.
  Android 7.0 ou plus récent.
- **PC Windows** (écran) : téléchargez
  [`scam-setup.exe`](https://github.com/ShinezeoGame/sCam/releases/latest/download/scam-setup.exe)
  et lancez-le. L'application n'est pas signée : si Windows affiche « Windows a protégé votre
  ordinateur », cliquez sur « Informations complémentaires » puis « Exécuter quand même ».
  Au premier lancement, **autorisez sCam sur les réseaux privés** quand le pare-feu le
  demande, sinon les caméras restent invisibles.

Tous les appareils doivent être sur le **même Wi-Fi**.

## Préparer la caméra

1. Ouvrez sCam, choisissez **Caméra** et donnez-lui un nom (« Chambre de Léo »).
2. Autorisez la caméra, le micro et les notifications quand Android le demande.
3. La caméra démarre aussitôt. Posez le téléphone (un support ou une pile de livres suffit),
   **branchez-le**, et éteignez l'écran si vous voulez : sCam continue, une notification
   permanente le rappelle.
4. Dans **Réglages → Économie de batterie**, touchez **Autoriser**. Sur un Samsung, vérifiez
   aussi dans les réglages d'Android : Applications → sCam → Batterie → **Non restreinte**.
   Sans cela, le téléphone peut endormir sCam au bout de quelques minutes.

Ne fermez pas sCam depuis la liste des applications récentes : la caméra s'arrêterait.

### Avec un PC Windows

Le PC peut aussi servir de caméra, avec sa webcam et son micro : choisissez **Caméra** au
premier lancement (ou dans les réglages), et autorisez sCam sur les réseaux privés quand le
pare-feu le demande (sinon les écrans ne le joignent pas). Laissez sCam ouvert, la fenêtre
peut être réduite : le PC ne se met pas en veille tant qu'il filme, mais l'écran peut
s'éteindre. Sous Windows, la caméra n'a ni lampe, ni choix d'objectif, et n'enregistre pas
d'extraits ; le niveau sonore et le mouvement y sont mesurés une fois par seconde environ.

## Appairer un écran

1. Sur la caméra, touchez **Appairer un écran** : l'appairage reste ouvert trois minutes.
2. Sur l'écran (votre téléphone ou le PC), ouvrez sCam, choisissez **Écran**, puis
   **Ajouter une caméra**. La caméra apparaît dans la liste : touchez **Appairer**.
3. Un code à six chiffres s'affiche **sur les deux appareils**. S'il est identique, touchez
   **Même code** des deux côtés. S'il diffère, refusez : quelqu'un d'autre essaie de se
   glisser entre les deux.

Si la caméra n'apparaît pas (certaines box bloquent les annonces), saisissez son adresse,
indiquée en bas de ses réglages, dans « Par son adresse ».

## Regarder et écouter

- Touchez une caméra pour voir l'image et entendre le son.
- **Son** coupe ou rétablit le son ; **Éclaircir** rend l'image plus lisible dans une pièce
  sombre (sur cet écran seulement) ; **Lampe** allume la lampe du téléphone caméra ;
  **Plein écran** agrandit l'image (touchez-la pour revenir).
- **Écouter en arrière-plan** : le son continue quand vous quittez la page ; sur Android,
  aussi quand vous quittez sCam ou éteignez l'écran. Un bandeau « À l'écoute » sur l'accueil
  permet de l'arrêter.

## Les alertes

Les réglages d'une caméra (sur la caméra, ou depuis un écran, page de la caméra) :

- **Alerte bruit** : un bruit qui dépasse le seuil pendant plus d'une seconde environ. Le
  curseur va de « Bruit fort » à « Murmure » ; le niveau actuel s'affiche juste dessous, le
  trait marque le seuil.
- **Alerte mouvement** : une partie de l'image change. Le curseur va de « Grands gestes » à
  « Moindre détail ». Un changement de lumière d'ensemble (une lampe qu'on allume) n'est pas
  compté comme un mouvement.

Après une alerte, la même caméra attend 30 secondes avant d'en envoyer une autre du même
genre. Les alertes arrivent sur **tous** les écrans appairés : en notification sur Android
(même en arrière-plan, si « Alertes en arrière-plan » est activé), et en faisant clignoter la
fenêtre sur Windows (laissez sCam ouvert, même réduit).

## Les extraits vidéo

Avec **Extraits vidéo** activé (réglages de la caméra, activé par défaut), une caméra
Android enregistre à chaque alerte les **30 secondes qui suivent**, image et son. Une
alerte qui arrive pendant un enregistrement ne lance pas d'extrait de plus. La caméra garde
les 30 derniers extraits ; au-delà, les plus anciens sont effacés.

Sur l'écran, la page de la caméra montre la section **Extraits** :

- ⬇ **Télécharger** : l'extrait voyage par la liaison chiffrée, puis il est rangé dans la
  galerie du téléphone (Films/sCam) ou, sur le PC, dans le dossier Vidéos\sCam ;
- ▶ **Ouvrir** : une fois téléchargé, il s'ouvre avec le lecteur vidéo de l'appareil ;
- 🗑 **Effacer** : l'extrait est effacé de la caméra (une copie téléchargée reste).

Sur la caméra elle-même, la section **Extraits** permet aussi de les effacer, un par un ou
tous.

## sDash et Home Assistant

Sur la caméra, **Réglages → Flux MJPEG local** : sCam affiche l'adresse du flux
(`http://…:47881/video.mjpg`), celle d'une image fixe (`…/image.jpg`), l'utilisateur
(`scam`) et le mot de passe.

Dans Home Assistant, ajoutez l'intégration **MJPEG IP Camera** avec ces informations.

Ce flux n'est **pas chiffré** : il est protégé par mot de passe et réservé au réseau local,
mais quelqu'un qui espionnerait votre Wi-Fi pourrait le voir. Il ne transporte que l'image,
deux fois par seconde. Laissez-le désactivé si vous ne vous en servez pas.

## En cas de souci

- **La caméra n'apparaît pas** : même Wi-Fi des deux côtés ? Sur le PC, sCam est-il autorisé
  sur les réseaux privés dans le pare-feu ? Essayez l'ajout par adresse.
- **« Caméra injoignable »** : la caméra est-elle allumée, sCam ouvert dessus, sur le Wi-Fi ?
  L'écran réessaie tout seul.
- **La caméra s'arrête au bout d'un moment** : retirez sCam de l'économie de batterie (voir
  plus haut) et laissez le téléphone branché.
- **« Cette caméra ne reconnaît plus cet écran »** : elle a été oubliée ou réinstallée.
  Oubliez-la sur l'écran et appairez-les de nouveau.

## Confidentialité et sécurité

- sCam ne fonctionne que sur le réseau de la maison : il n'utilise aucun serveur, et refuse
  toute connexion venue d'une adresse qui n'est pas locale.
- L'appairage échange des clés (X25519) et fait vérifier un code à six chiffres sur les deux
  appareils. Ensuite, chaque connexion est authentifiée et tous les messages sont chiffrés
  (AES-256-GCM). L'image et le son passent par WebRTC, chiffré lui aussi (DTLS-SRTP).
- Un appareil non appairé ne reçoit ni image, ni son, ni même l'état de la caméra.
- Seul le flux MJPEG facultatif n'est pas chiffré (voir plus haut).
- Le direct n'est jamais enregistré. Seuls les extraits d'alerte le sont (si l'option est
  activée), sur la caméra elle-même, puis sur l'écran qui les télécharge.
