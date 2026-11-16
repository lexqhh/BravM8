# FlyMedia

Add-on WoW: Forever : pendant les vols de maître de vol, des images et des clips apparaissent quelques secondes au milieu de l'écran, à des moments aléatoires.

## Pour toi : ajouter des médias

1. Sur la page GitHub du dépôt, ouvre le dossier `medias/`, clique sur **Add file → Upload files** et glisse tes images, GIF ou vidéos.
2. Valide (**Commit changes**).
3. Au bout de 1 à 2 minutes, une nouvelle version apparaît dans **Releases** : tout est converti au format WoW automatiquement.

Pour retirer un média, supprime-le du dossier `medias/` de la même façon.

Formats : images png/jpg/webp/bmp, clips gif/mp4/webm/mov/mkv (lus en entier jusqu'à 60 s, son de la vidéo inclus). Pour mettre un son sur une image, ajoute un fichier audio du même nom (`chat.jpg` + `chat.mp3`).

Les réglages (taille max, images par seconde, durée des clips) sont en haut de `tools/build.py`.

## Pour tes potes : installer et mettre à jour

1. Télécharger **FlyMedia.bat** depuis la dernière Release.
2. Double-cliquer dessus. Si Windows affiche « Windows a protégé votre ordinateur », cliquer sur **Informations complémentaires → Exécuter quand même**.
3. Le programme trouve WoW: Forever, installe l'add-on, ajoute un raccourci **Mettre à jour FlyMedia** sur le bureau et propose la mise à jour automatique au démarrage de Windows.

Ensuite, il n'y a plus rien à faire (ou un double-clic sur le raccourci). Si WoW est ouvert pendant la mise à jour, les nouveaux médias apparaissent au prochain lancement du jeu.

## En jeu

Pendant un vol : une première image apparaît 3 à 6 s après le décollage, avec le son de montée de niveau. Chaque image reste 5 s (un clip reste le temps de sa durée), puis disparaît. La suivante apparaît après une pause aléatoire de 8 à 18 s, et ainsi de suite jusqu'à l'atterrissage : environ 4 images sur un vol d'1 min, 8 sur 2 min.

1 vol sur 6, la 2e image est remplacée par un son rare (dossier `medias/easter/`).

Au survol : **Muet** et **X** (plus rien jusqu'à l'atterrissage). On ne peut pas passer une image. Glisser pour déplacer, Ctrl + molette pour la taille.

| Commande | Effet |
|---|---|
| `/flymedia` | état et aide |
| `/flymedia on` / `off` | activer ou désactiver |
| `/flymedia test` | faire apparaître une image tout de suite |
| `/flymedia son` | couper ou remettre le son |
| `/flymedia duree 5` | secondes d'affichage |
| `/flymedia pause 8 18` | pause aléatoire entre deux apparitions |
| `/flymedia taille 1.2` | taille de la fenêtre |
| `/flymedia verrou` | bloquer le déplacement |
| `/flymedia reset` | remettre la fenêtre au centre |

## Construire en local (facultatif)

```bash
pip install pillow
python tools/build.py --version 1 --repo pseudo/FlyMedia
```

Il faut ffmpeg dans le PATH. Le résultat est dans `dist/`.
