# BravM8

Add-on WoW: Forever : pendant les vols de maître de vol, des images et des clips apparaissent quelques secondes au milieu de l'écran, à des moments aléatoires.

## Pour toi : ajouter des médias

1. Sur la page GitHub du dépôt, ouvre le dossier `medias/`, clique sur **Add file → Upload files** et glisse tes images, GIF ou vidéos.
2. Valide (**Commit changes**).
3. Au bout de 1 à 2 minutes, une nouvelle version apparaît dans **Releases** : tout est converti au format WoW automatiquement.

GitHub refuse les fichiers de plus de 25 Mo envoyés par le site. Pour une vidéo trop lourde, glisse-la sur `tools/reduire-video.bat` : une copie en 480p (quelques Mo) est créée dans un dossier `pour-BravM8` à côté de l'originale. Aucune perte en jeu, les clips y sont affichés en 200 px.

Pour retirer un média, supprime-le du dossier `medias/` de la même façon.

Formats : images png/jpg/webp/bmp, clips gif/mp4/webm/mov/mkv (lus en entier jusqu'à 60 s, son de la vidéo inclus). Pour mettre un son sur une image, ajoute un fichier audio du même nom (`chat.jpg` + `chat.mp3`).

Les réglages (taille max, images par seconde, durée des clips) sont en haut de `tools/build.py`.

## Pour tes potes : installer et mettre à jour

1. Télécharger **BravM8.bat** depuis la dernière Release.
2. Double-cliquer dessus. Si Windows affiche « Windows a protégé votre ordinateur », cliquer sur **Informations complémentaires → Exécuter quand même**.
3. Le programme trouve WoW: Forever, installe l'add-on, ajoute un raccourci **Mettre à jour BravM8** sur le bureau et propose la mise à jour automatique au démarrage de Windows.

Ensuite, il n'y a plus rien à faire (ou un double-clic sur le raccourci). Si WoW est ouvert pendant la mise à jour, les nouveaux médias apparaissent au prochain lancement du jeu.

## En jeu

Pendant un vol : une première image apparaît 3 à 6 s après le décollage, avec le son de montée de niveau. Chaque image reste 5 s (un clip reste le temps de sa durée), puis disparaît. La suivante apparaît après une pause aléatoire de 5 à 12 s, et ainsi de suite jusqu'à l'atterrissage : environ 5 images sur un vol d'1 min, 9 à 10 sur 2 min.

1 vol sur 6, la 2e image est remplacée par un son rare (dossier `medias/easter/`).

Hors vol : une image apparaît aussi **à la mort du personnage** et **pendant l'incantation de la pierre de foyer** (elle reste jusqu'à la fin de l'incantation et disparaît si on l'annule).

Dans le **sac de couchage douillet** (Cozy Sleeping Bag) : un diaporama démarre quand on se couche dessus, les images apparaissent au même rythme que pendant un vol (pause de 5 à 12 s, environ 12 images sur la sieste). Il s'arrête quand le bonus d'XP atteint 3 %, après 3 min 10, si on sort de la zone du sac ou si un combat commence.

Au survol : **Muet** et **X** (plus rien jusqu'à l'atterrissage). On ne peut pas passer une image. Glisser pour déplacer, Ctrl + molette pour la taille.

| Commande | Effet |
|---|---|
| `/bravm8` | état et aide |
| `/bravm8 on` / `off` | activer ou désactiver |
| `/bravm8 test` | faire apparaître une image tout de suite |
| `/bravm8 son` | couper ou remettre le son |
| `/bravm8 mort` | activer ou désactiver l'image à la mort |
| `/bravm8 foyer` | activer ou désactiver l'image pendant la pierre de foyer |
| `/bravm8 sac` | activer ou désactiver le diaporama dans le sac de couchage |
| `/bravm8 duree 5` | secondes d'affichage |
| `/bravm8 pause 5 12` | pause aléatoire entre deux apparitions |
| `/bravm8 taille 1.2` | taille de la fenêtre |
| `/bravm8 verrou` | bloquer le déplacement |
| `/bravm8 reset` | remettre la fenêtre au centre |

## Construire en local (facultatif)

```bash
pip install pillow
python tools/build.py --version 1 --repo pseudo/BravM8
```

Il faut ffmpeg dans le PATH. Le résultat est dans `dist/`.
