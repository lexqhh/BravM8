# Idées pour plus tard

## Rendre les médias privés via le VPS

**But :** que les images et vidéos ne soient plus publiques.

**Problème :** si on passe le dépôt GitHub en privé tel quel, le .bat ne peut plus télécharger les versions, donc l'installation et les mises à jour cassent. **Ne pas passer le dépôt en privé avant que ce qui suit soit en place.**

**Plan :**
1. Sur le VPS : servir un dossier en HTTPS (nginx, Caddy…) à une adresse difficile à deviner, par ex. `https://domaine/flymedia-<code-secret>/`.
2. GitHub Actions : après la conversion, envoyer `FlyMedia.zip`, `version.txt` et `update.ps1` sur le VPS (`scp` ou `rsync` avec une clé SSH rangée dans les secrets du dépôt).
3. `FlyMedia.bat` et `update.ps1` : remplacer l'adresse `github.com/.../releases/latest/download` par celle du VPS.
4. Publier une dernière version sur GitHub (encore public) pour que les potes reçoivent le nouveau script, ou leur renvoyer le nouveau .bat.
5. Passer le dépôt en privé. Les Actions restent gratuites (2 000 min/mois pour un dépôt privé, une publication prend environ 1 min).

**À préparer :** l'accès SSH au VPS, savoir s'il y a déjà un serveur web et un nom de domaine.
